//
//  ListingDetailView.swift
//  Exchange
//
//  Presentation-only version: contains only layout & formatting.
//  No data fetching, no logging, no Cloudflare signing, no gallery.
//




import SwiftUI
import Foundation
import UIKit
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

struct CartItem: Identifiable {
    let id: UUID
    var listingId: String? = nil
    var sellerId: String? = nil
    var title: String
    var price: Double
    var tax: Double
    var quantity: Int
    var imageName: String
}

// MARK: - Simple disk-backed cache for ListingHit + Hero URL (per listingId)
enum DiskListingCache {
    // Directory under Library/CachesShe
    private static var baseDir: URL = {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("ListingDetailCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func hitPath(for id: String) -> URL {
        baseDir.appendingPathComponent("hit_\(id).json", conformingTo: .json)
    }
    private static func heroPath(for id: String) -> URL {
        baseDir.appendingPathComponent("hero_\(id).json", conformingTo: .json)
    }

    private static func heroImagePath(for id: String) -> URL {
        baseDir.appendingPathComponent("heroimg_\(id).jpg")
    }

    struct HeroEntry: Codable {
        let url: String
        let exp: Int
    }

    @discardableResult
    static func saveHeroImage(_ data: Data, for id: String) -> Bool {
        let url = heroImagePath(for: id)
        do {
            try data.write(to: url, options: .atomic)
            #if DEBUG
            print("💾 [DiskCache] saved hero image id=\(id) bytes=\(data.count)")
            #endif
            return true
        } catch {
            #if DEBUG
            print("⚠️ [DiskCache] save hero image failed id=\(id) error=\(error.localizedDescription)")
            #endif
            return false
        }
    }

    static func loadHeroImage(for id: String) -> UIImage? {
        let url = heroImagePath(for: id)
        guard let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else { return nil }
        #if DEBUG
        print("💾 [DiskCache] hit (HeroImage) id=\(id) bytes=\(data.count)")
        #endif
        return img
    }

    // ListingHit must be Codable-compatible payload. We store the Algolia hit object as Data.
    static func saveHit(_ hit: ListingHit, for id: String) {
        do {
            let data = try JSONEncoder().encode(hit)
            try data.write(to: hitPath(for: id), options: .atomic)
            #if DEBUG
            print("💾 [DiskCache] saved hit for id=\(id) bytes=\(data.count)")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [DiskCache] save hit failed id=\(id) error=\(error.localizedDescription)")
            #endif
        }
    }

    static func loadHit(for id: String) -> ListingHit? {
        let url = hitPath(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let hit = try JSONDecoder().decode(ListingHit.self, from: data)
            #if DEBUG
            print("💾 [DiskCache] hit (ListingHit) id=\(id) bytes=\(data.count)")
            #endif
            return hit
        } catch {
            #if DEBUG
            print("⚠️ [DiskCache] decode hit failed id=\(id) error=\(error.localizedDescription)")
            #endif
            return nil
        }
    }

    static func saveHero(url: URL, exp: Int, for id: String) {
        let entry = HeroEntry(url: url.absoluteString, exp: exp)
        do {
            let data = try JSONEncoder().encode(entry)
            try data.write(to: heroPath(for: id), options: .atomic)
            #if DEBUG
            print("💾 [DiskCache] saved hero id=\(id) exp=\(exp)")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [DiskCache] save hero failed id=\(id) error=\(error.localizedDescription)")
            #endif
        }
    }

    static func loadHero(for id: String, now: Int = Int(Date().timeIntervalSince1970)) -> URL? {
        let url = heroPath(for: id)
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(HeroEntry.self, from: data) else { return nil }
        if entry.exp > now, let u = URL(string: entry.url) {
            #if DEBUG
            print("💾 [DiskCache] hit (Hero) id=\(id) exp=\(entry.exp)")
            #endif
            return u
        } else {
            // expired or bad URL; remove it
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// Return the set of listingIds that currently have any cache on disk.
    static func cachedListingIds() -> Set<String> {
        var ids = Set<String>()
        guard let files = try? FileManager.default.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) else {
            return ids
        }
        for f in files {
            let name = f.lastPathComponent
            if name.hasPrefix("hit_"), let id = name.split(separator: "_").dropFirst().joined().split(separator: ".").first {
                ids.insert(String(id))
            } else if name.hasPrefix("hero_"), let id = name.split(separator: "_").dropFirst().joined().split(separator: ".").first {
                ids.insert(String(id))
            } else if name.hasPrefix("heroimg_"), let id = name.split(separator: "_").dropFirst().joined().split(separator: ".").first {
                ids.insert(String(id))
            }
        }
        return ids
    }

    /// Remove cache for a single listing id (both hit + hero), if present.
    @discardableResult
    static func removeAll(for id: String) -> Bool {
        var removed = false
        let hit = hitPath(for: id)
        let hero = heroPath(for: id)
        let heroImg = heroImagePath(for: id)
        if FileManager.default.fileExists(atPath: hit.path) {
            try? FileManager.default.removeItem(at: hit)
            removed = true
        }
        if FileManager.default.fileExists(atPath: hero.path) {
            try? FileManager.default.removeItem(at: hero)
            removed = true
        }
        if FileManager.default.fileExists(atPath: heroImg.path) {
            try? FileManager.default.removeItem(at: heroImg)
            removed = true
        }
        #if DEBUG
        if removed { print("🗑️ [DiskCache] removed listingId=\(id)") }
        #endif
        return removed
    }

    /// Purge any **unliked** cache entries older than a cutoff. If a hero entry has an `exp` in the past,
    /// it is treated as stale even if its mtime is recent.
    /// - Parameters:
    ///   - olderThanDays: age threshold in days (default 14)
    ///   - likedIds: the set of listingIds that should be preserved
    /// - Returns: (removed, kept) counts for diagnostics
    @discardableResult
    static func purgeStaleUnliked(olderThanDays: Int = 14, likedIds: Set<String> = []) -> (removed: Int, kept: Int) {
        let cutoff = Date().addingTimeInterval(TimeInterval(-olderThanDays * 24 * 60 * 60))
        let fm = FileManager.default
        var removed = 0
        var kept = 0

        guard let files = try? fm.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return (0,0)
        }

        // Group files by listingId
        var grouped: [String: [URL]] = [:]
        for f in files {
            let name = f.lastPathComponent
            var id: String?
            if name.hasPrefix("hit_") {
                id = String(name.dropFirst(4)).components(separatedBy: ".").first
            } else if name.hasPrefix("hero_") {
                id = String(name.dropFirst(5)).components(separatedBy: ".").first
            } else if name.hasPrefix("heroimg_") {
                id = String(name.dropFirst(8)).components(separatedBy: ".").first
            }
            if let id {
                grouped[id, default: []].append(f)
            }
        }

        for (id, urls) in grouped {
            // Keep anything explicitly liked
            if likedIds.contains(id) {
                kept += 1
                continue
            }

            // Determine staleness: (a) all files older than cutoff OR (b) hero entry expired
            var allOlderThanCutoff = true
            var heroExpired = false

            for url in urls {
                if let attrs = try? fm.attributesOfItem(atPath: url.path),
                   let mtime = attrs[.modificationDate] as? Date {
                    if mtime > cutoff { allOlderThanCutoff = false }
                }

                if url.lastPathComponent.hasPrefix("hero_"),
                   let data = try? Data(contentsOf: url),
                   let entry = try? JSONDecoder().decode(HeroEntry.self, from: data) {
                    let now = Int(Date().timeIntervalSince1970)
                    if entry.exp <= now { heroExpired = true }
                }
            }

            if allOlderThanCutoff || heroExpired {
                if removeAll(for: id) { removed += 1 } else { kept += 1 }
            } else {
                kept += 1
            }
        }

        #if DEBUG
        print("🧹 [DiskCache] purgeStaleUnliked(days=\(olderThanDays)) removed=\(removed) kept=\(kept)")
        #endif
        return (removed, kept)
    }
}


// Helper shape for rounding only the top corners of a rectangle
private struct TopRoundedRectangle: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Pure UI Layout

/// Minimal model the layout can consume. You can construct this from Algolia/Firestore elsewhere.
public struct ListingDetailProps: Equatable {
    public struct SellerSummary: Equatable {
        public var username: String
        public var avatarURL: URL?
        public var productsCount: Int
        public var followersCount: Int
        public var isFollowing: Bool
        public init(username: String, avatarURL: URL?, productsCount: Int, followersCount: Int, isFollowing: Bool) {
            self.username = username
            self.avatarURL = avatarURL
            self.productsCount = productsCount
            self.followersCount = followersCount
            self.isFollowing = isFollowing
        }
    }

    public var listingId: String
    public var title: String
    public var description: String
    public var brand: String
    public var price: String
    public var heroURL: URL?

    // New (optional) seller block for the UI row
    public var seller: SellerSummary?
    // Optional action that the host can hook to follow/unfollow
    public var onToggleFollow: (() -> Void)?

    public init(listingId: String, title: String, brand: String, price: String, heroURL: URL?, seller: SellerSummary? = nil, onToggleFollow: (() -> Void)? = nil, description: String = "") {
        self.listingId = listingId
        self.title = title
        self.description = description
        self.brand = brand
        self.price = price
        self.heroURL = heroURL
        self.seller = seller
        self.onToggleFollow = onToggleFollow
    }
    // Custom Equatable implementation ignoring the onToggleFollow closure
    public static func == (lhs: ListingDetailProps, rhs: ListingDetailProps) -> Bool {
        return lhs.listingId == rhs.listingId
            && lhs.title == rhs.title
            && lhs.description == rhs.description
            && lhs.brand == rhs.brand
            && lhs.price == rhs.price
            && lhs.heroURL == rhs.heroURL
            && lhs.seller == rhs.seller
        // NOTE: closures are not Equatable; we intentionally ignore `onToggleFollow`
    }
}

public struct ListingDetailView: View {
    public let props: ListingDetailProps
    @State private var quantity: Int = 1
    @State private var showGallery: Bool = false // kept only to preserve layout hooks if needed
    @State private var cartItem: CartItem? = nil
    // Hero image target height (60% of screen height)
    private let heroHeight: CGFloat = UIScreen.main.bounds.height * 0.6

    // Preferred display name for seller/nav: username if available, otherwise brand (trimmed)
    private var preferredSellerName: String {
        if let name = props.seller?.username.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return props.brand.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(props: ListingDetailProps) {
        self.props = props
    }

    // MARK: - Subviews (layout only)

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fm", Double(n)/1_000_000.0) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n)/1_000.0) }
        return "\(n)"
    }

    @ViewBuilder
    private func LikeCountPill(_ count: Int) -> some View {
        // Layout placeholder; no logic
        EmptyView()
    }

    @ViewBuilder
    private func TitleRow() -> some View {
        HStack(alignment: .top) {
            Text(props.title.isEmpty ? "Listing" : props.title)
                .font(.title3).bold()
                .multilineTextAlignment(.leading)
            Spacer()
            LikeCountPill(0)
        }
    }

    @ViewBuilder
    private func SellerRow() -> some View {
        let s = props.seller
        HStack(spacing: 12) {
            // Avatar (only if available; no placeholder icon)
            if let url = s?.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray5))
                            .frame(width: 44, height: 44)
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    case .failure:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            // Username + counts
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    let displayName = preferredSellerName.isEmpty ? "Seller" : preferredSellerName
                    Text(displayName)
                        .font(.headline)
#if DEBUG
                        .onAppear { print("👤 [SellerRow] rendering name='\(displayName)' (seller.username=\(s?.username ?? "nil"))") }
#endif
                }
                let products = formatCount(s?.productsCount ?? 0)
                let followers = formatCount(s?.followersCount ?? 0)
                Text("\(products) Products · \(followers) Followers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { props.onToggleFollow?() }) {
                Text((s?.isFollowing ?? false) ? "Following" : "Follow")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color(.systemGray6)))
            }
            .buttonStyle(.plain)
        }
    }


    // Precompute to help SwiftUI's type inference (keeps `body` simpler)
    private var heroURLForRender: URL? { props.heroURL }

    @ViewBuilder
    private func HeroSection() -> some View {
        ZStack(alignment: .topTrailing) {
            if let cachedImg = DiskListingCache.loadHeroImage(for: props.listingId) {
                Image(uiImage: cachedImg)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight)
                    .clipped()
                    .onTapGesture { showGallery = true }
            } else if let url = heroURLForRender {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: heroHeight)
                            .background(Color(.systemGray6))
                            .clipped()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: heroHeight)
                            .clipped()
                            .onTapGesture { showGallery = true }
                    case .failure:
                        VStack {
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 80)
                                .foregroundStyle(.secondary)
                            Text("Image unavailable").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: heroHeight)
                        .background(Color(.systemGray6))
                        .clipped()
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight)
                    .background(Color(.systemGray6))
                    .clipped()
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private func CardContent() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TitleRow()

            // Item description
            if !props.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(props.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SellerRow()
            // QuantitySelector() removed
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            TopRoundedRectangle(radius: 24)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .padding(.top, -80)
        .padding(.bottom, 120)
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HeroSection()
                CardContent()
            }
        }
        .navigationTitle(preferredSellerName.isEmpty ? "Detail Product" : preferredSellerName)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            BottomBar(price: props.price, onAddToCart: {
                // convert "$18.00" → 18.0
                let numericPrice: Double = {
                    let cleaned = props.price.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
                    return Double(cleaned) ?? 0.0
                }()

                let item = CartItem(
                    id: UUID(),
                    listingId: props.listingId,
                    sellerId: props.seller?.username,
                    title: props.title.isEmpty ? props.brand : props.title,
                    price: numericPrice,
                    tax: 0.0,
                    quantity: 1,
                    imageName: props.heroURL?.absoluteString ?? ""
                )
                self.cartItem = item
            })
            .background(.ultraThinMaterial)
        }
        .sheet(item: $cartItem) { item in
            CartScreen(incomingItem: item)
        }
        .onAppear {
            #if DEBUG
            print("🧭 [Nav] ListingDetailView appear id=\(props.listingId) brand=\(props.brand) price=\(props.price) hero=\(props.heroURL?.absoluteString ?? "nil")")
            print("🏷️ [Nav] title='\(preferredSellerName.isEmpty ? (props.brand.isEmpty ? "Detail Product" : props.brand) : preferredSellerName)' (username vs brand)")
            if let s = props.seller {
                print("👤 [SellerRow] username='\(s.username)' brandFallback='\(props.brand)'")
            } else {
                print("👤 [SellerRow] no seller on props; brandFallback='\(props.brand)'")
            }
            #endif
        }
        .onDisappear {
            #if DEBUG
            print("🧭 [Nav] ListingDetailView disappear id=\(props.listingId)")
            #endif
        }
    }
}

private struct BottomBar: View {
    let price: String
    var onAddToCart: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Price").font(.caption).foregroundStyle(.secondary)
                Text(price.isEmpty ? "$—" : price).font(.title3).bold()
            }
            Spacer()
            Button(action: onAddToCart) {
                HStack(spacing: 8) {
                    Image(systemName: "cart.fill")
                    Text("Buy").bold()
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Buy this item for \(price.isEmpty ? "price unavailable" : price)")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - Loader Container (fetch + sign, then render presentation-only view)

import AlgoliaSearchClient
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

/// Use this container when you only have a `listingId`. It will:
/// 1) fetch the full listing from Algolia
/// 2) pick an image id (preferred → primary → first of imageIds)
/// 3) sign the private Cloudflare `card` variant (fallback to public Thumbnail)
/// 4) render `ListingDetailView` with constructed props
public struct ListingDetailContainer: View {
    public let listingId: String
    // MARK: - Ephemeral in-memory caches (per process)
    private static var hitCache: [String: ListingHit] = [:] // listingId -> hit
    // key = "\(imageId)#\(variant.rawValue)" ; value = (url, expEpochSec)
    private static var heroCache: [String: (url: URL, exp: Int)] = [:]
    private static let cacheQueue = DispatchQueue(label: "ListingDetailContainer.Cache", qos: .userInitiated)
    @State private var props: ListingDetailProps?

    public init(listingId: String) {
        self.listingId = listingId
    }

    public var body: some View {
        Group {
            if let props {
                ListingDetailView(props: props)
            } else {
                ProgressView()
                    .task { await load() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            #if DEBUG
            print("🧭 [Nav] ListingDetailContainer appear listingId=\(listingId)")
            #endif
            // Run a lightweight, throttled disk purge (once a day) for unliked items & expired heroes.
            let lastKey = "ListingDiskCache.lastPurge"
            let now = Date()
            let last = UserDefaults.standard.object(forKey: lastKey) as? Date ?? .distantPast
            if now.timeIntervalSince(last) > 24 * 60 * 60 {
                UserDefaults.standard.set(now, forKey: lastKey)
                Task.detached {
                    // TODO: Pass your liked listingIds set here to preserve liked items.
                    _ = DiskListingCache.purgeStaleUnliked(olderThanDays: 14, likedIds: [])
                }
            }
        }
        .onDisappear {
            #if DEBUG
            print("🧭 [Nav] ListingDetailContainer disappear listingId=\(listingId)")
            #endif
        }
    }

    // MARK: - Cache helpers

    private func cacheKey(imageId: String, variant: CFVariant) -> String {
        return "\(imageId)#\(variant.rawValue)"
    }

    private func nowEpoch() -> Int {
        return Int(Date().timeIntervalSince1970)
    }

    private func getCachedHit(listingId: String) -> ListingHit? {
        return Self.cacheQueue.sync {
            return Self.hitCache[listingId]
        }
    }

    private func setCachedHit(_ hit: ListingHit, for listingId: String) {
        Self.cacheQueue.async {
            Self.hitCache[listingId] = hit
        }
    }

    private func getCachedHeroURL(imageId: String, variant: CFVariant) -> URL? {
        return Self.cacheQueue.sync {
            let key = cacheKey(imageId: imageId, variant: variant)
            if let entry = Self.heroCache[key] {
                if entry.exp > nowEpoch() {
                    return entry.url
                } else {
                    // expired; drop it
                    Self.heroCache.removeValue(forKey: key)
                }
            }
            return nil
        }
    }

    private func setCachedHeroURL(_ url: URL, exp: Int, imageId: String, variant: CFVariant) {
        Self.cacheQueue.async {
            let key = cacheKey(imageId: imageId, variant: variant)
            Self.heroCache[key] = (url, exp)
        }
    }

    #if canImport(FirebaseFirestore)
    /// Lightweight fetch of seller summary (products count, followers count, follow state).
    private func fetchSellerSummary(sellerId: String, fallbackUsername: String) async -> ListingDetailProps.SellerSummary? {
        let db = Firestore.firestore()
        do {
            // Username & (optional) avatar from users/{uid}
            let userDoc = try await db.collection("users").document(sellerId).getDocument()
            let username = (userDoc.get("username") as? String)
                            ?? (userDoc.get("usernameLower") as? String)
                            ?? fallbackUsername
            let avatarStr = (userDoc.get("photoURL") as? String) ?? (userDoc.get("avatarURL") as? String)
            let avatarURL = avatarStr.flatMap(URL.init(string:))

            // Count active products (unsold listings)
            let listingsQuery = db.collection("users").document(sellerId).collection("listings").whereField("sold", isEqualTo: false)
            let listingsAgg = try await listingsQuery.count.getAggregation(source: .server)
            let productsCount = listingsAgg.count.intValue

            // Followers count via aggregation on /users/{uid}/followers
            let followersQuery = db.collection("users").document(sellerId).collection("followers")
            let followersAgg = try await followersQuery.count.getAggregation(source: .server)
            let followersCount = followersAgg.count.intValue

            // Is current user following?
            var isFollowing = false
            #if canImport(FirebaseAuth)
            if let me = Auth.auth().currentUser?.uid {
                let followDoc = try await db.collection("users").document(sellerId).collection("followers").document(me).getDocument()
                isFollowing = followDoc.exists
            }
            #endif

            return ListingDetailProps.SellerSummary(
                username: username,
                avatarURL: avatarURL,
                productsCount: productsCount,
                followersCount: followersCount,
                isFollowing: isFollowing
            )
        } catch {
            #if DEBUG
            print("⚠️ [SellerSummary] fetch failed uid=\(sellerId) error=\(error.localizedDescription)")
            #endif
            return ListingDetailProps.SellerSummary(
                username: fallbackUsername,
                avatarURL: nil,
                productsCount: 0,
                followersCount: 0,
                isFollowing: false
            )
        }
    }
    #endif

    // MARK: - Data Load

    private func load() async {
        #if DEBUG
        print("🧭 [Nav] ListingDetailContainer load() start listingId=\(listingId)")
        #endif
        // Try disk cache first for the ListingHit
        if let diskHit = DiskListingCache.loadHit(for: listingId) {
            #if DEBUG
            print("💾 [DiskCache] using cached ListingHit for id=\(listingId)")
            #endif
            setCachedHit(diskHit, for: listingId)
        }
        do {
            // 1) Full record (cache first)
            let hit: ListingHit
            if let cached = getCachedHit(listingId: listingId) {
                hit = cached
            } else {
                let fetched: ListingHit = try await fetchHit(listingId: listingId)
                setCachedHit(fetched, for: listingId)
                DiskListingCache.saveHit(fetched, for: listingId)
                hit = fetched
            }

            // 2) Select image id
            let imageId = hit.preferredImageId ?? hit.primaryImageId ?? hit.imageIds?.first

            #if DEBUG
            print("🖼️ [Image] selected imageId=\(imageId ?? "nil") from hit \(hit.listingID)")
            #endif

            // 3) Build hero URL: prefer signed private `card`, fallback to public Thumbnail
            var hero: URL? = nil
            // Try disk hero (per listingId) before in-memory hero cache
            if hero == nil, let diskHero = DiskListingCache.loadHero(for: listingId) {
                hero = diskHero
                #if DEBUG
                print("💾 [DiskCache] hero URL hit -> \(diskHero.absoluteString)")
                #endif
            }
            // Try hero cache (imageId+variant) to avoid re-signing and re-downloading
            if let id = imageId, let cachedHero = getCachedHeroURL(imageId: id, variant: .card) {
                hero = cachedHero
                #if DEBUG
                print("💾 [HeroCache] hit -> \(cachedHero.absoluteString)")
                #endif
            }
            if let id = imageId {
                if hero == nil {
                    hero = await detailSignImage(id: id, variant: .card)
                    #if DEBUG
                    print("🖋️ [Signer] signedURL=\(hero?.absoluteString ?? "nil")")
                    #endif
                }
                if hero == nil {
                    var pub = CFImages.publicURL(id: id, variant: .thumbnail)
                    // Force JPEG to avoid CoreGraphics 24-bpp decode bug on iOS 18 (rdar://143602439)
                    if let u = pub, var comps = URLComponents(url: u, resolvingAgainstBaseURL: false) {
                        var items = comps.queryItems ?? []
                        let hasFormat = items.contains { $0.name == "format" || $0.name == "f" }
                        if !hasFormat { items.append(URLQueryItem(name: "format", value: "jpeg")) }
                        comps.queryItems = items
                        pub = comps.url
                    }
                    hero = pub
                    #if DEBUG
                    print("🌐 [Fallback] publicURL=\(hero?.absoluteString ?? "nil")")
                    #endif
                }
            } else {
                #if DEBUG
                print("⚠️ [Image] No valid imageId found for listingId=\(listingId)")
                #endif
            }

            // Persist hero image bytes to disk for instant next-run paint
            if let heroURL = hero {
                // If we don't already have a cached hero image file for this listing, fetch and save it.
                if DiskListingCache.loadHeroImage(for: listingId) == nil {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: heroURL)
                        if !data.isEmpty {
                            _ = DiskListingCache.saveHeroImage(data, for: listingId)
                        }
                    } catch {
                        #if DEBUG
                        print("⚠️ [DiskCache] fetch hero image failed id=\(listingId) url=\(heroURL.absoluteString) error=\(error.localizedDescription)")
                        #endif
                    }
                }
            }

            // 4) Map to props and enrich with seller stats from Firestore if available
            // Try to get username fields if they exist on the ListingHit type.
            let reflectedUsername: String? = (
                Mirror(reflecting: hit).children.first { $0.label == "username" }?.value as? String
                ?? Mirror(reflecting: hit).children.first { $0.label == "usernameLower" }?.value as? String
            )

            // Fallback display name if username is missing
            let displayUsername: String = {
                let candidate = (reflectedUsername ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty { return candidate }
                // As a last resort, use the brand to avoid "Seller" placeholder
                return (hit.brand ?? "")
            }()

            // Extract sellerId. Prefer `userId` if present, otherwise parse it from the Firestore `path` like
            // "users/{uid}/listings/{listingId}".
            func extractSellerId(from hit: ListingHit) -> String? {
                if let userIdAny = Mirror(reflecting: hit).children.first(where: { $0.label == "userId" })?.value,
                   let uid = userIdAny as? String, !uid.isEmpty {
                    #if DEBUG
                    print("👤 [LDHost] sellerId from hit.userId -> \(uid)")
                    #endif
                    return uid
                }
                if let pathAny = Mirror(reflecting: hit).children.first(where: { $0.label == "path" })?.value,
                   let path = pathAny as? String, !path.isEmpty {
                    // Expected shape: "users/{uid}/listings/{listingId}"
                    let parts = path.split(separator: "/").map(String.init)
                    if parts.count >= 4, parts[0] == "users" {
                        let uid = parts[1]
                        #if DEBUG
                        print("👤 [LDHost] sellerId parsed from path '\(path)' -> \(uid)")
                        #endif
                        return uid
                    }
                }
                #if DEBUG
                print("⚠️ [LDHost] unable to extract sellerId; username from hit = \(reflectedUsername ?? "nil")")
                #endif
                return nil
            }

            let sellerId = extractSellerId(from: hit)

            // Build a minimal seller summary up-front, then enrich from Firestore if we have a sellerId.
            var sellerSummary: ListingDetailProps.SellerSummary? = ListingDetailProps.SellerSummary(
                username: displayUsername,
                avatarURL: nil,
                productsCount: 0,
                followersCount: 0,
                isFollowing: false
            )

#if canImport(FirebaseFirestore)
            if let sellerId {
                if let enriched = await fetchSellerSummary(sellerId: sellerId, fallbackUsername: displayUsername) {
                    sellerSummary = enriched
                }
            }
#endif

            // Build seller username from hit (prefer username/usernameLower; fallback to brand)
            let sellerUsername: String = {
                let u1 = (Mirror(reflecting: hit).children.first { $0.label == "username" }?.value as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                let u2 = (Mirror(reflecting: hit).children.first { $0.label == "usernameLower" }?.value as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                let brand = (hit.brand ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let u1, !u1.isEmpty { return u1 }
                if let u2, !u2.isEmpty { return u2 }
                return brand
            }()
#if DEBUG
            print("👤 [LDHost] mapping seller → username='\(sellerUsername)' (brandFallback='\(hit.brand ?? "")')")
#endif
            sellerSummary = ListingDetailProps.SellerSummary(
                username: sellerUsername,
                avatarURL: nil,
                productsCount: 0,
                followersCount: 0,
                isFollowing: false
            )
            let mapped = ListingDetailProps(
                listingId: listingId,
                title: hit.title ?? "",
                brand: hit.brand ?? "",
                price: hit.priceString ?? "",
                heroURL: hero,
                seller: sellerSummary,
                onToggleFollow: nil,
                description: hit.description ?? ""
            )
#if DEBUG
            print("👤 [LDHost] props.seller.username='\(mapped.seller?.username ?? "nil")'")
#endif

            // Persist hero if it came from cache and we can infer an expiry (optional)
            if let id = imageId, let cached = getCachedHeroURL(imageId: id, variant: .card),
               let exp = (try? URLComponents(url: cached, resolvingAgainstBaseURL: false))?.queryItems?.first(where: { $0.name == "exp" })?.value.flatMap(Int.init) {
                DiskListingCache.saveHero(url: cached, exp: exp, for: listingId)
            }

            #if DEBUG
            let memHeroMatch = (imageId != nil) && (getCachedHeroURL(imageId: imageId!, variant: .card)?.absoluteString == hero?.absoluteString)
            let diskHeroMatch = (DiskListingCache.loadHero(for: listingId)?.absoluteString == hero?.absoluteString)
            print("[ListingDetailContainer] ✅ Mapped listingId=\(listingId) -> hero=\(hero?.absoluteString ?? "nil") cached(mem)=\(memHeroMatch) cached(disk)=\(diskHeroMatch)")
            #endif

            DispatchQueue.main.async {
                self.props = mapped
            }

        } catch {
            #if DEBUG
            print("[ListingDetailContainer] load error:", error)
            #endif
        }
    }

    /// Call the Firebase callable to sign a private Cloudflare image variant.
    /// Uses the project CFVariant enum for type safety, but passes its raw value to the backend.
    private func detailSignImage(id: String, variant: CFVariant, ttl: Int = 3600) async -> URL? {
        #if canImport(FirebaseFunctions)
        do {
            let result = try await Functions.functions(region: "us-central1")
                .httpsCallable("getSignedImageUrl")
                .call([
                    "id": id,
                    "variant": variant.rawValue,
                    "ttlSec": ttl,
                    "probe": true
                ])
            if let dict = result.data as? [String: Any],
               let ok = dict["ok"] as? Bool, ok,
               let urlStr = dict["url"] as? String {
                // Surface expiry/status for any listeners (e.g., SellerProfileView / LikesVM)
                let exp = (dict["exp"] as? NSNumber)?.intValue
                let status = (dict["status"] as? NSNumber)?.intValue
                #if DEBUG
                if let exp {
                    print("✅ [LDHost] signer ok variant=\(variant.rawValue) status=\(status ?? 0) url=\(urlStr) exp=\(exp)")
                } else {
                    print("✅ [LDHost] signer ok variant=\(variant.rawValue) status=\(status ?? 0) url=\(urlStr)")
                }
                #endif

                // Workaround iOS 18 CoreGraphics bug for certain formats (rdar://143602439):
                // force JPEG decoding by appending format=jpeg (signature only covers exp/path)
                var finalURLString = urlStr
                if var comps = URLComponents(string: urlStr) {
                    var items = comps.queryItems ?? []
                    let hasFormat = items.contains { $0.name == "format" || $0.name == "f" }
                    if !hasFormat { items.append(URLQueryItem(name: "format", value: "jpeg")) }
                    comps.queryItems = items
                    if let s = comps.string { finalURLString = s }
                }

                // Broadcast so upstream views can memoize the hero
                NotificationCenter.default.post(
                    name: Notification.Name("HeroURLCached"),
                    object: nil,
                    userInfo: [
                        "listingId": self.listingId,
                        "imageId": id,
                        "variant": variant.rawValue,
                        "url": finalURLString,
                        "exp": exp as Any
                    ].compactMapValues { $0 }
                )

                // Persist to in-memory hero cache until `exp`
                if let exp = exp, let url = URL(string: finalURLString) {
                    setCachedHeroURL(url, exp: exp, imageId: id, variant: variant)
                    DiskListingCache.saveHero(url: url, exp: exp, for: self.listingId)
                }

                return URL(string: finalURLString)
            }
        } catch {
            #if DEBUG
            print("[ListingDetailContainer] signer error:", error.localizedDescription)
            #endif
        }
        #endif
        return nil
    }

    // MARK: - Secure Fetch using short-lived key
    private func fetchHit(listingId: String) async throws -> ListingHit {
        // Use the secured key from Functions (same logic as InstantSearchCoordinator)
        let secured = try await SearchKey.current()

        let client = SearchClient(
            appID: ApplicationID(rawValue: secured.appId),
            apiKey: APIKey(rawValue: secured.apiKey)
        )

        // Use your production index
        let index = client.index(withName: IndexName("LoomPair"))

        #if DEBUG
        let started = Date()
        print("🔎 [Algolia] getObject start id=\(listingId) index=\(index.name.rawValue)")
        #endif

        do {
            let attrs: [Attribute] = [
                "objectID","listingID","brand","category","subcategory","size","condition","gender",
                "description","color","originalPrice","listingPrice","primaryImageId","preferredImageId",
                "imageIds","imageURLs","createdAt","path",
                // Ensure seller identity arrives on direct getObject as well
                "username","usernameLower","userId"
            ].map { Attribute(rawValue: $0) }
            let obj: ListingHit = try await index.getObject(
                withID: ObjectID(rawValue: listingId),
                attributesToRetrieve: attrs
            )
            #if DEBUG
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            print("✅ [Algolia] getObject done id=\(listingId) in \(ms)ms")
            #endif
            return obj
        } catch {
            // fallback search by listingID field
            var q = Query()
            q.hitsPerPage = 1
            q.filters = "listingID:\"\(listingId)\""
            q.attributesToRetrieve = [
                "objectID","listingID","brand","category","subcategory","size","condition","gender",
                "description","color","originalPrice","listingPrice","primaryImageId","preferredImageId",
                "imageIds","imageURLs","createdAt","path",
                // NEW: ensure we get seller identity for UI
                "username","usernameLower","userId"
            ]

            let res = try await index.search(query: q)
            if let first = res.hits.first,
               let data = try? JSONEncoder().encode(first.object),
               let hit = try? JSONDecoder().decode(ListingHit.self, from: data) {
                #if DEBUG
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                print("✅ [Algolia] search-by-listingID hit id=\(listingId) in \(ms)ms")
                #endif
                return hit
            }

            #if DEBUG
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            print("❌ [Algolia] no hit for id=\(listingId) after \(ms)ms error=\(error)")
            #endif
            throw error
        }
    }
}
