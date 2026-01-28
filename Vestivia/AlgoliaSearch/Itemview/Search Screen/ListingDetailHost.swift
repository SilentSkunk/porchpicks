// ListingDetailHost.swift

import SwiftUI
import FirebaseFunctions
import Foundation

// MARK: - Signed URL in-memory cache (avoid re-signing & re-downloading during TTL)

fileprivate struct CachedSignedURL {
    let url: URL
    let expEpoch: TimeInterval // seconds since epoch (as returned by the function)
}

fileprivate final class SignedImageURLCache {
    static let shared = SignedImageURLCache()
    private var store: [String: CachedSignedURL] = [:]
    private let lock = NSLock()

    private func key(id: String, variant: CFVariant) -> String { "\(id)#\(variant.rawValue)" }

    /// Returns a cached URL if it hasn't expired yet.
    func url(for id: String, variant: CFVariant, now: TimeInterval = Date().timeIntervalSince1970) -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = store[key(id: id, variant: variant)] else { return nil }
        // if expEpoch <= 0, treat as already expired
        guard entry.expEpoch > now else {
            store.removeValue(forKey: key(id: id, variant: variant))
            return nil
        }
        return entry.url
    }

    /// Save a signed URL with an expiration epoch (seconds since Jan 1, 1970).
    func set(_ url: URL, for id: String, variant: CFVariant, expEpoch: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        store[key(id: id, variant: variant)] = CachedSignedURL(url: url, expEpoch: expEpoch)
    }
}

struct ListingDetailHost: View {
    let hit: ListingHit
    @State private var props: ListingDetailProps

    // signed hero url we’ll feed to the presentation view
    @State private var heroURL: URL?
    @State private var isLoading = true
    @State private var username: String? = nil

    #if DEBUG
    private func debugSellerTrace() {
        print("👤 [LDHost] seller from hit → username=\(hit.username ?? "nil"), usernameLower=\(hit.usernameLower ?? "nil"), userId=\(hit.userId ?? "nil") | resolved=\(self.username ?? "nil")")
    }
    #endif

    init(hit: ListingHit) {
        self.hit = hit
        let brand = (hit.brand ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let u1 = hit.username?.trimmingCharacters(in: .whitespacesAndNewlines)
        let u2 = hit.usernameLower?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sellerUsername = (u1?.isEmpty == false ? u1! : (u2?.isEmpty == false ? u2! : brand))
        let sellerSummary = ListingDetailProps.SellerSummary(
            username: sellerUsername,
            avatarURL: nil,
            productsCount: 0,
            followersCount: 0,
            isFollowing: false
        )
        _props = State(initialValue: ListingDetailProps(
            listingId: hit.listingID,
            title: hit.title,
            brand: brand,
            price: hit.priceString,
            heroURL: nil,
            seller: sellerSummary,
            onToggleFollow: nil,
            description: hit.description ?? ""
        ))
        #if DEBUG
        print("👤 [LDHost] initial props.seller.username='\(sellerSummary.username)' (brand='\(brand)')")
        #endif
    }

    var body: some View {
        ListingDetailView(props: props)
        .task(id: hit.listingID) {
            // Populate username for the UI (Algolia may give either cased or lowercased)
            self.username = hit.username ?? hit.usernameLower
            #if DEBUG
            print("👤 [LDHost] onAppear seller='\(props.seller?.username ?? "nil")'")
            debugSellerTrace()
            #endif
            await loadSignedHero()
        }
    }

    // MARK: - Signing + debug

    private func loadSignedHero() async {
        isLoading = true

        // 1) choose an image id (preferred → primary → first)
        let imageId = hit.preferredImageId ?? hit.primaryImageId ?? hit.imageIds?.first

        #if DEBUG
        print("🖼️ [LDHost] listingId=\(hit.listingID) brand=\(hit.brand ?? "") chosenImageId=\(imageId ?? "nil")")
        #endif

        // Try memory cache first (avoid re-signing/re-downloading within TTL)
        if let id = imageId, let cached = SignedImageURLCache.shared.url(for: id, variant: .card) {
            #if DEBUG
            print("💾 [LDHost] cache hit → using signed hero: \(cached.absoluteString)")
            #endif
            heroURL = cached
            // also update props so the detail view sees the hero immediately
            props = ListingDetailProps(
                listingId: props.listingId,
                title: props.title,
                brand: props.brand,
                price: props.price,
                heroURL: cached,
                seller: props.seller,
                onToggleFollow: props.onToggleFollow,
                description: props.description
            )
            isLoading = false
            return
        }

        guard let id = imageId else {
            #if DEBUG
            print("⚠️ [LDHost] no image id available; skipping signer")
            #endif
            heroURL = nil
            isLoading = false
            return
        }

        // 2) Request a signed URL so UI can start rendering immediately
        if let (signedURL, expEpoch) = await signImageViaFunctionWithExp(id: id, variant: .card) {
            #if DEBUG
            let expStr = Date(timeIntervalSince1970: expEpoch)
            print("🖋️ [LDHost] signed hero URL -> \(signedURL.absoluteString) (exp \(expStr))")
            #endif
            heroURL = signedURL
            props = ListingDetailProps(
                listingId: props.listingId,
                title: props.title,
                brand: props.brand,
                price: props.price,
                heroURL: signedURL,
                seller: props.seller,
                onToggleFollow: props.onToggleFollow,
                description: props.description
            )
            SignedImageURLCache.shared.set(signedURL, for: id, variant: .card, expEpoch: expEpoch)
        } else {
            // 3) Fallback to a public thumbnail (at least show something)
            let fallback = CFImages.publicURL(id: id, variant: .thumbnail)
            #if DEBUG
            print("🌐 [LDHost] signer failed; fallback public -> \(fallback?.absoluteString ?? "nil")")
            #endif
            heroURL = fallback
            props = ListingDetailProps(
                listingId: props.listingId,
                title: props.title,
                brand: props.brand,
                price: props.price,
                heroURL: fallback,
                seller: props.seller,
                onToggleFollow: props.onToggleFollow,
                description: props.description
            )
        }

        isLoading = false
    }

    /// Calls your callable `getSignedImageUrl` and returns a URL if successful.
    private func signImageViaFunction(id: String, variant: CFVariant, ttl: Int = 3600) async -> URL? {
        do {
            let fn = Functions.functions(region: "us-central1").httpsCallable("getSignedImageUrl")
            // IMPORTANT: use the **exact** variant string your backend expects
            let result = try await fn.call([
                "id": id,
                "variant": variant.rawValue,   // e.g. "Card" if your CFVariant is cased like that
                "ttlSec": ttl,
                "probe": true                  // optional; backend HEAD-checks and returns status
            ])

            if let dict = result.data as? [String: Any],
               (dict["ok"] as? Bool) == true,
               let urlStr = dict["url"] as? String,
               let url = URL(string: urlStr) {

                #if DEBUG
                let status = (dict["status"] as? Int) ?? 0
                print("✅ [LDHost] signer ok variant=\(variant.rawValue) status=\(status) url=\(urlStr)")
                #endif
                return url
            } else {
                #if DEBUG
                print("❌ [LDHost] signer returned unexpected payload: \(String(describing: result.data))")
                #endif
            }
        } catch {
            #if DEBUG
            print("❌ [LDHost] signer call failed: \(error.localizedDescription)")
            #endif
        }
        return nil
    }

    /// Same as `signImageViaFunction` but also returns the expiration epoch so we can cache by TTL.
    private func signImageViaFunctionWithExp(id: String, variant: CFVariant, ttl: Int = 3600) async -> (URL, TimeInterval)? {
        do {
            let fn = Functions.functions(region: "us-central1").httpsCallable("getSignedImageUrl")
            let result = try await fn.call([
                "id": id,
                "variant": variant.rawValue,
                "ttlSec": ttl,
                "probe": true
            ])

            if let dict = result.data as? [String: Any],
               (dict["ok"] as? Bool) == true,
               let urlStr = dict["url"] as? String,
               let url = URL(string: urlStr) {

                let status = (dict["status"] as? Int) ?? 0
                let exp = (dict["exp"] as? Double) ?? (Date().timeIntervalSince1970 + Double(ttl)) // fallback
                #if DEBUG
                print("✅ [LDHost] signer ok variant=\(variant.rawValue) status=\(status) url=\(urlStr) exp=\(Int(exp))")
                #endif
                return (url, exp)
            } else {
                #if DEBUG
                print("❌ [LDHost] signer (withExp) returned unexpected payload: \(String(describing: result.data))")
                #endif
            }
        } catch {
            #if DEBUG
            print("❌ [LDHost] signer (withExp) call failed: \(error.localizedDescription)")
            #endif
        }
        return nil
    }
}
