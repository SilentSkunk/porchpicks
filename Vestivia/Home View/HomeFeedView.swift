//
//  HomeFeedView.swift
//  Vestivia
//
//  Created by William Hunsucker on 7/16/25.
//

import SwiftUI
import Foundation
import FirebaseAuth

import AlgoliaSearchClient
import FirebaseFirestore


struct HomeFeedView: View {
    @Binding var selectedTab: AppTab
    @Binding var showingSellOptions: Bool
    @State private var navigateToSingle = false
    @State private var searchText = ""
    @State private var selectedBrand: String = ""
    @State private var showRecentSearchesPage = false
    @State private var randomBrands: [Brand] = []
    @State private var showSearchResults = false
    @Binding var navigateToSiblings: Bool
    @State private var isSiblingSet: Bool = true
    @State private var showSideMenu = false
    @Binding var isLoggedIn: Bool
    
    // MARK: - Newest Items (Algolia)
    @StateObject private var newestVM = NewestItemsVM()
    
    private let menuWidth: CGFloat = 220

    // Feature flag — show "Sellers You Follow" section
    private let showFollowedSellers = true  // Show "Sellers You Follow" section
    
    // Feature flag — hide Recent Price Drop until it's implemented
    private let showRecentPriceDrop = false
    
/// Inject the actual Messages destination view from the caller to avoid a hard dependency here.
var makeMessagesDestination: () -> AnyView = { AnyView(MessagesHomeView()) }
    
    // Local navigation for pushing subpages (modern NavigationStack)
    enum InnerRoute: Hashable { case messages, profile }
    @State private var path: [InnerRoute] = []
    
    private func pushToShop(with query: String) {
        selectedTab = .shop
        NotificationCenter.default.post(name: .shopSearchRequested, object: query)
    }
    
    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .leading) {
                mainContent
                    .overlay(overlayDimmer)
                sideMenuLayer
            }
            .navigationDestination(for: InnerRoute.self) { route in
                switch route {
                case .messages:
                    makeMessagesDestination()
                case .profile:
                    ConnectedProfileView()
                        .eraseToAnyView()
                }
            }
            .onChange(of: path) { _, newPath in
                #if DEBUG
                print("[HomeFeedView] path:", newPath)
                #endif
            }
            .task {
                #if DEBUG
                print("[HomeFeedView] NewestItemsVM initial load")
                #endif
                newestVM.load(limit: 12, forceRefresh: true)
            }
        }
    }
    
    @ViewBuilder
    private var searchBarView: some View {
        SearchBar(searchText: $searchText, onSubmit: {
            pushToShop(with: searchText)
        }, showSideMenu: $showSideMenu)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .zIndex(1)
    }

    @ViewBuilder
    private var scrollContent: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionHeader(title: "New Items")
                        .headerStyle()
                    Group {
                        if newestVM.isLoading {
                            // simple skeleton while loading
                            FeaturedItemCard()
                                .redacted(reason: .placeholder)
                        } else if let error = newestVM.errorMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Failed to load: \(error)")
                                    .foregroundColor(.secondary)
                                Button("Retry") {
                                    newestVM.load(limit: 12, forceRefresh: true)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else if newestVM.items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No new items yet")
                                    .foregroundColor(.secondary)
                                Button("Refresh") {
                                    newestVM.load(limit: 12, forceRefresh: true)
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            NewestItemsRow(items: newestVM.items) { _ in
                                // Hook up navigation to Shop/Detail if desired
                                selectedTab = .shop
                            }
                        }
                    }

                    if showFollowedSellers {
                        SectionHeader(title: "Sellers You Follow")
                            .headerStyle()
                        HorizontalScrollItems(count: 4)
                    }

                    if showRecentPriceDrop {
                        SectionHeader(title: "Recent Price Drop")
                            .headerStyle()
                        VerticalListItems(count: 2)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 0)
                .frame(minHeight: geometry.size.height - 40, alignment: .top)
                .background(GeometryReader { innerGeo in
                    Color.clear
                        .preference(key: ScrollViewOffsetPreferenceKey.self, value: innerGeo.frame(in: .global).minY)
                })
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            searchBarView
            scrollContent
        }
    }

    @ViewBuilder
    private var overlayDimmer: some View {
        Group {
            if showSideMenu {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation { showSideMenu = false }
                    }
            }
        }
    }

    @ViewBuilder
    private var sideMenuLayer: some View {
        SideMenuView(
            showSideMenu: $showSideMenu,
            isLoggedIn: $isLoggedIn,
            onMessages: {
                path.append(.messages)
            },
            onProfile: {
                path.append(.profile)
            }
        )
        .frame(width: menuWidth)
        .offset(x: showSideMenu ? 0 : -menuWidth)
        .transition(.move(edge: .leading))
        .animation(.easeInOut(duration: 0.25), value: showSideMenu)
        .zIndex(11)
    }
    
    struct SearchBar: View {
        @Binding var searchText: String
        var onSubmit: () -> Void
        @Binding var showSideMenu: Bool

        var body: some View {
            HStack {
                Image(systemName: "line.horizontal.3")
                    .accessibilityLabel("Menu")
                    .accessibilityHint("Opens the navigation menu")
                    .onTapGesture {
                        withAnimation {
                            showSideMenu.toggle()
                        }
                    }
                TextField("Search for items, brands, or sellers", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        if !searchText.isEmpty {
                            onSubmit()
                        }
                    }
                Spacer()
                Image(systemName: "bell")
                    .accessibilityLabel("Notifications")
                    .accessibilityHint("View your notifications")
                Image(systemName: "cart")
                    .accessibilityLabel("Cart")
                    .accessibilityHint("View your shopping cart")
            }
            .padding(.horizontal, 16)
        }
    }
    
    struct SectionHeader: View {
        var title: String
        var onTap: (() -> Void)? = nil
        
        var body: some View {
            HStack {
                Text(title)
                    .headerStyle()
                Spacer()
                Image(systemName: "chevron.right")
                    .onTapGesture {
                        onTap?()
                    }
            }
        }
    }
    
    struct HorizontalScrollItems: View {
        var count: Int
        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(0..<count, id: \.self) { index in
                        VStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 100, height: 100)
                            Text("Label \(index + 1)")
                                .bodyStyle()
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    struct FeaturedItemCard: View {
        var body: some View {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 200)
                .overlay(
                    VStack {
                        Spacer()
                        HStack {
                            Text("Artist")
                                .bodyStyle()
                            Text("New Drop")
                                .bodyStyle()
                            Spacer()
                            Image(systemName: "play.circle")
                        }
                        .padding()
                    }
                )
        }
    }
    
    struct VerticalListItems: View {
        var count: Int
        var body: some View {
            VStack(spacing: 12) {
                ForEach(0..<count, id: \.self) { _ in
                    HStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 60)
                        VStack(alignment: .leading) {
                            Text("Headline").bold()
                            Text("Description placeholder...")
                                .bodyStyle()
                                .foregroundColor(.gray)
                            Text("Today • 23 min")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
            }
        }
    }
    
    struct ScrollViewOffsetPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
    
    
    
    struct SideMenuView: View {
        @Binding var showSideMenu: Bool
        @Binding var isLoggedIn: Bool
        let onMessages: () -> Void
        let onProfile: () -> Void
        var body: some View {
            VStack(alignment: .leading, spacing: 32) {
                Spacer().frame(height: 60)
                Button(action: {
                    withAnimation { showSideMenu = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onMessages()
                    }
                }) {
                    HStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.title2)
                            .foregroundColor(.black)
                        Text("Messages")
                            .font(.headline)
                            .foregroundColor(.black)
                    }
                    .padding(.leading, 24)
                }
                Button(action: {
                    #if DEBUG
                    print("Profile tapped")
                    #endif
                    withAnimation {
                        showSideMenu = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onProfile()
                    }
                }) {
                    HStack(spacing: 16) {
                        Image(systemName: "person.circle")
                            .font(.title2)
                            .foregroundColor(.black)
                        Text("Profile")
                            .font(.headline)
                            .foregroundColor(.black)
                    }
                    .padding(.leading, 24)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .edgesIgnoringSafeArea(.vertical)
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 2, y: 0)
        }
    }
}

// MARK: - ViewModel to pull "Newest Items" from Algolia + Firestore beacon + 4h cache
final class NewestItemsVM: ObservableObject {
    @Published var items: [ListingHit] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Base index and optional replica sorted by createdAt desc
    private let baseIndexName = "LoomPair"
    private let newestReplicaName = "LoomPair_createdAt_desc"

    // ---- Cache config ----
    private let cacheFileName = "newest-items-cache.json"
    private let cacheTTL: TimeInterval = 4 * 60 * 60 // 4 hours

    private struct CacheEnvelope: Codable {
        let fetchedAt: Date
        let items: [ListingHit]
    }

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent(cacheFileName)
    }

    // ---- Firestore beacon ----
    // Collection/document and field names for the "latest createdAt" beacon
    private let beaconCollection = "meta"
    private let beaconDocument = "newestListings"
    // Preferred field is `latestCreatedAt` (Timestamp). Fallback to `updatedAt`.
    private let beaconFields: [String] = ["latestCreatedAt", "updatedAt"]

    // Public entrypoint
    @MainActor
    func load(limit: Int = 10, forceRefresh: Bool = false) {
        #if DEBUG
        print("[NewestItemsVM] load(limit: \(limit), forceRefresh: \(forceRefresh))")
        #endif

        // 1) Try cache first for instant paint
        if let cached = readCache() {
            self.items = cached.items

            if !forceRefresh {
                Task {
                    let needsRefresh = await self.shouldRefreshCache(lastFetchedAt: cached.fetchedAt)
                    if needsRefresh { await self.fetchFromAlgolia(limit: limit) }
                }
                return
            }
        } else {
            // No cache; show loading skeleton immediately
            self.isLoading = true
        }

        // If no cache (or forcing), fetch now.
        Task { await fetchFromAlgolia(limit: limit) }
    }

    // MARK: - Decide whether to refresh using the beacon
    private func shouldRefreshCache(lastFetchedAt: Date) async -> Bool {
        do {
            let beaconDate = try await loadBeaconDate()
            // If the beacon is newer than our cached timestamp, refresh.
            return beaconDate > lastFetchedAt
        } catch {
            // If the beacon fails (offline, perms, missing), fall back to TTL:
            // refresh only when cache is older than TTL.
            let age = Date().timeIntervalSince(lastFetchedAt)
            return age >= cacheTTL
        }
    }

    private func loadBeaconDate() async throws -> Date {
        let db = Firestore.firestore()
        let snap = try await db.collection(beaconCollection).document(beaconDocument).getDocument()
        guard let data = snap.data() else {
            throw NSError(domain: "NewestItemsVM", code: 1, userInfo: [NSLocalizedDescriptionKey: "Beacon doc missing"])
        }
        for key in beaconFields {
            if let ts = data[key] as? Timestamp {
                return ts.dateValue()
            }
        }
        throw NSError(domain: "NewestItemsVM", code: 2, userInfo: [NSLocalizedDescriptionKey: "Beacon fields missing"])
    }

    // MARK: - Network fetch + cache
    @MainActor
    private func fetchFromAlgolia(limit: Int) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let secured = try await SearchKey.current()
            let client = SearchClient(
                appID: ApplicationID(rawValue: secured.appId),
                apiKey: APIKey(rawValue: secured.apiKey)
            )

            let indexName: IndexName = await Self.indexExists(client: client, name: newestReplicaName)
                ? IndexName(rawValue: newestReplicaName)
                : IndexName(rawValue: baseIndexName)

            var q = Query()
            q.hitsPerPage = limit
            q.attributesToRetrieve = [
                "objectID","listingID","brand","category","subcategory","size","condition","gender",
                "description","color","originalPrice","listingPrice","primaryImageId","preferredImageId",
                "imageIds","imageURLs","createdAt","path","username","sold"
            ]
            q.filters = "sold:false"

            let res = try await client.index(withName: indexName).search(query: q)

            let decoded: [ListingHit] = res.hits.compactMap {
                guard let data = try? JSONEncoder().encode($0.object) else { return nil }
                return try? JSONDecoder().decode(ListingHit.self, from: data)
            }

            self.items = decoded
            self.isLoading = false

            // Persist to cache with timestamp
            saveCache(items: decoded)
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Cache IO
    private func readCache() -> CacheEnvelope? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CacheEnvelope.self, from: data)
    }

    private func saveCache(items: [ListingHit]) {
        let env = CacheEnvelope(fetchedAt: Date(), items: items)
        if let data = try? JSONEncoder().encode(env) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    // MARK: - Helpers
    private static func indexExists(client: SearchClient, name: String) async -> Bool {
        do { _ = try await client.index(withName: IndexName(rawValue: name)).getSettings(); return true }
        catch { return false }
    }
}

// MARK: - UI Pieces for "Newest Items"
private struct NewestItemsRow: View {
    let items: [ListingHit]
    var onTap: (ListingHit) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(items, id: \.objectID) { hit in
                    VStack(alignment: .leading, spacing: 8) {
                        // Simple placeholder card; replace with your real thumbnail view
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 140, height: 160)
                            .overlay(
                                Text(hit.brand ?? "")
                                    .font(.footnote)
                                    .padding(6),
                                alignment: .bottomLeading
                            )
                        Text("$\(hit.listingPrice ?? "")")
                            .font(.subheadline).bold()
                    }
                    .onTapGesture { onTap(hit) }
                }
            }
            .padding(.horizontal)
        }
    }
}

private extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}

extension Notification.Name {
    static let shopSearchRequested = Notification.Name("ShopSearchRequested")
}
