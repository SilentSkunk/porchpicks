// MARK: - Image ID helpers
private func nonEmptyOrNil(_ s: String?) -> String? {
guard let v = s?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
return v
}

private func firstUsableImageId(for hit: ListingHit) -> String? {
    // Prefer primary -> preferred -> first in imageIds
    if let p = nonEmptyOrNil((Mirror(reflecting: hit).children.first { $0.label == "primaryImageId" }?.value as? String)) {
        return p
    }
    if let pref = nonEmptyOrNil((Mirror(reflecting: hit).children.first { $0.label == "preferredImageId" }?.value as? String)) {
        return pref
    }
    if let arr = Mirror(reflecting: hit).children.first(where: { $0.label == "imageIds" })?.value as? [String] {
        return arr.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }
    return nil
}

/// Extract a stable listing identifier from a hit (prefers `listingID`, falls back to `objectID`)
private func listingIdentifier(for hit: ListingHit) -> String? {
if let id = Mirror(reflecting: hit).children.first(where: { $0.label == "listingID" })?.value as? String,
   !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    return id
}
if let oid = Mirror(reflecting: hit).children.first(where: { $0.label == "objectID" })?.value as? String,
   !oid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    return oid
}
return nil
}

/// Public utility for views to get a **public** Thumbnail URL for a hit (always-present variant).
func publicThumbURL(for hit: ListingHit) -> URL? {
guard let id = firstUsableImageId(for: hit) else { return nil }
return CFImages.publicThumbURL(id: id)
}


import Foundation
import SwiftUI
import InstantSearch
import InstantSearchSwiftUI
import AlgoliaSearchClient



/// Navigation destinations for the search flow
enum ListingRoute: Hashable { case listingID(String) }

/// Owns the InstantSearch objects and wires them together.
/// Uses secured, short-lived Algolia keys fetched from Firebase Functions (no long-lived key in app).
final class InstantSearchCoordinator: ObservableObject {
    // Expose these to the SwiftUI view
    let searchBoxController = SearchBoxObservableController()
    let hitsController = HitsObservableController<ListingHit>()

    /// Navigation stack path so views can drive deep links (e.g. from push)
    @Published var path = NavigationPath() {
        didSet {
            #if DEBUG
            let oldCount = oldValue.count
            let newCount = path.count
            let delta = newCount - oldCount
            let deltaStr = delta >= 0 ? "+\(delta)" : "\(delta)"
            print("🧭 [Nav] path.count changed: \(oldCount) → \(newCount) [\(deltaStr)]")
            #endif
        }
    }

// Keep strong refs to searcher/connectors so they don't deinit
private var searcher: HitsSearcher?
private let searchBoxInteractor = SearchBoxInteractor()
private let hitsInteractor = HitsInteractor<ListingHit>()
private var searchBoxConnector: SearchBoxConnector?
private var hitsConnector: HitsConnector<ListingHit>?

// One-shot guard to avoid duplicate secured setup calls
private var setupTask: Task<Void, Never>? = nil

// Predefined facet lists (controllers/connectors are owned by this helper)
let facets: FacetFilters
// All facet selection/clearing is handled by `FacetFilters`; this coordinator does not mutate FilterState facets directly.

/// True when there is no typed query and no active facet refinements.
var shouldShowFeatured: Bool {
    let noQuery = searchBoxController.query.isEmpty
    let noFacets = filterState.description.isEmpty
    return noQuery && noFacets
}

// Retain connections so they don't deinit (required by InstantSearch)
private var connections: [Connection] = []

// Algolia + Firebase
private var client: SearchClient?
private let filterState = FilterState()

// Local cache for the first page of the default (empty) feed
private let defaultFeedCache = DefaultFeedCache<ListingHit>()

// Keep the last tapped hit so the detail screen can render instantly when possible
private var lastSelectedHitById: [String: ListingHit] = [:]

// One-shot flag for initial preload
private var didKickInitialPreload = false

// Init with your index name (App ID + key are fetched securely at runtime)
init(indexName: String = "LoomPair") {
    // Build fixed facet lists wired to the same FilterState
    self.facets = FacetFilters(filterState: filterState)
    // Kick secured setup once; subsequent calls will no-op via `setupTask` guard
    ensureSetup(indexName: indexName)
}
/// Ensure the secured Algolia client is set up exactly once.
/// Safe to call multiple times (e.g., from App root and screens); only the first call does work.
func ensureSetup(indexName: String) {
    // If a client already exists, we're done
    if client != nil { return }
    // If a setup task is already running, reuse it
    if setupTask != nil { return }
    setupTask = Task { [weak self] in
        guard let self = self else { return }
        await self.setupSecuredAlgolia(indexName: indexName)
        // Clear the task handle after finishing so a future retry can happen if needed
        await MainActor.run { [weak self] in self?.setupTask = nil }
    }
}

// MARK: - Lightweight hits cache (query + filters -> hits)
private struct CacheEntry {
    let items: [ListingHit]
    let fetchedAt: Date
}
private var hitsCache: [String: CacheEntry] = [:]
private let hitsCacheTTL: TimeInterval = 10 * 60 // 10 minutes

/// Stable-ish key from current query + filters + page + hitsPerPage
private func currentCacheKey() -> String {
    let q = searchBoxController.query.trimmingCharacters(in: .whitespacesAndNewlines)
    let facets = filterState.description // good enough; if needed, replace with explicit ordered signature
    let page = searcher?.request.query.page ?? 0
    let hpp = searcher?.request.query.hitsPerPage ?? 20
    return "q=\(q)|facets=\(facets)|p=\(page)|hpp=\(hpp)"
}

private func readHitsCache(for key: String) -> [ListingHit]? {
    guard let entry = hitsCache[key] else { return nil }
    guard Date().timeIntervalSince(entry.fetchedAt) < hitsCacheTTL else { return nil }
    return entry.items
}

private func writeHitsCache(_ items: [ListingHit], for key: String) {
    hitsCache[key] = CacheEntry(items: items, fetchedAt: Date())
}

/// Force a refresh from Algolia, optionally clearing the in-memory hits cache first.
@MainActor
func refreshResults(force: Bool = false) {
    if force {
        // clear all cached pages so the next search actually hits Algolia
        hitsCache.removeAll()
    }
    searcher?.request.query.page = 0
    searcher?.search()
}

/// Prefetch **public** Thumbnail URLs for visible hits (no signer; warms URLCache).
private func prefetchThumbs(for hits: [ListingHit]) {
    // Limit to first 30 to avoid excessive work during fast scrolling.
    let slice = hits.prefix(30)

    // Build public Cloudflare Images Thumbnail URLs.
    let urls: [URL] = slice.compactMap { hit in
        guard let id = firstUsableImageId(for: hit) else { return nil }
        return CFImages.publicThumbURL(id: id)
    }

    // Warm the shared URL cache. This is non-blocking and doesn't require Firebase/Functions.
    if !urls.isEmpty {
        ImagePrefetcher.prefetch(urls)
        #if DEBUG
        debugLog("prefetch thumbnails queued=\(urls.count)")
        #endif
    }
}


#if DEBUG
private func debugLog(_ message: String) {
    // debug logging disabled (no-op)
}
#endif

#if DEBUG
/// Pretty-print the important fields we expect from Algolia for each hit.
private func debugDumpHits(_ hits: [ListingHit], source: String) {
    print("🔎 [Algolia] \(source) decoded \(hits.count) hits")
    for (idx, h) in hits.enumerated() {
        let m = Mirror(reflecting: h)
        func getString(_ key: String) -> String? {
            return m.children.first { $0.label == key }?.value as? String
        }
        func getStrings(_ key: String) -> [String]? {
            return m.children.first { $0.label == key }?.value as? [String]
        }

        let listingID = getString("listingID") ?? "nil"
        let objectID  = getString("objectID")  ?? "nil"
        let brand     = getString("brand")     ?? "nil"
        let username  = getString("username")  ?? "nil"
        let usernameL = getString("usernameLower") ?? "nil"
        let userId    = getString("userId")    ?? "nil"
        let primId    = getString("primaryImageId") ?? "nil"
        let prefId    = getString("preferredImageId") ?? "nil"
        let imgIds    = getStrings("imageIds") ?? []
        let createdAt = getString("createdAt") ?? "nil"
        let path      = getString("path") ?? "nil"

        print("""
        🧩 [Hit \(idx)]
          listingID=\(listingID) objectID=\(objectID)
          brand=\(brand)
          username=\(username) usernameLower=\(usernameL) userId=\(userId)
          primaryImageId=\(primId) preferredImageId=\(prefId) imageIds.count=\(imgIds.count)
          createdAt=\(createdAt)
          path=\(path)
        """)
    }
}
#endif

// MARK: - Secure Algolia setup (fetch short-lived key from Firebase)
private func wireAfterClientReady(indexName: String) {
    guard let client = self.client else { return }

    let searcher = HitsSearcher(client: client, indexName: IndexName(rawValue: indexName))
    self.searcher = searcher

    // Connectors
    let sbc = SearchBoxConnector(
        searcher: searcher,
        interactor: searchBoxInteractor,
        searchTriggeringMode: .searchOnSubmit
    )
    sbc.connectController(searchBoxController)
    self.searchBoxConnector = sbc

    let hc = HitsConnector(searcher: searcher, interactor: hitsInteractor)
    hc.connectController(hitsController)
    self.hitsConnector = hc

    // Keep the request.filters in sync with FilterState and allow filtered searches.
    self.connections.append(searcher.connectFilterState(filterState))

    // Optional defaults
    searcher.request.query.hitsPerPage = 20

    // Ensure Algolia returns the fields we need for images and seller info
    searcher.request.query.attributesToRetrieve = [
        "objectID",
        "listingID",
        "brand",
        "category",
        "subcategory",
        "size",
        "condition",
        "gender",
        "description",
        "color",
        "originalPrice",
        "listingPrice",
        "primaryImageId",
        "preferredImageId",
        "imageIds",
        "imageURLs",
        "createdAt",
        "path",
        "username",
        "usernameLower",
        "userId"
    ]
    #if DEBUG
    print("🛰️ [Algolia][Request] attributesToRetrieve=\(searcher.request.query.attributesToRetrieve ?? [])")
    #endif

    // Wire result observer that saves the "default" feed to cache
    wireResultCaching(searcher: searcher)

    // Wire FilterState-driven behavior
    wireFilterDrivenSearch()
    
    // Kick initial preload on main actor
    Task { @MainActor in
        self.kickInitialPreloadIfNeeded()
    }
}

private func setupSecuredAlgolia(indexName: String) async {
    if client != nil { return }
    do {
        let secured = try await SearchKey.current()
        let client = SearchClient(
            appID: ApplicationID(rawValue: secured.appId),
            apiKey: APIKey(rawValue: secured.apiKey)
        )
        self.client = client
        await MainActor.run {
            self.wireAfterClientReady(indexName: indexName)
        }
    } catch {
        #if DEBUG
        debugLog("Failed to fetch secured Algolia key: \(error.localizedDescription)")
        #endif
    }
}

// MARK: - Caching & FilterState wiring

/// Observe search results and cache the first page when we're in the default context
private func wireResultCaching(searcher: HitsSearcher) {
    searcher.onResults.subscribe(with: self) { [weak self] _, response in
        guard let self = self else { return }
        // We only cache when there's no query and no active facet refinements
        let noQuery = self.searchBoxController.query.isEmpty
        let noFacets = self.filterState.description.isEmpty

        // Convert generic hits to strongly-typed objects
        let typedHits: [ListingHit] = response.hits.compactMap { hit in
            // Decode Algolia's JSON wrapper into our strongly-typed model
            guard let data = try? JSONEncoder().encode(hit.object) else { return nil }
            return try? JSONDecoder().decode(ListingHit.self, from: data)
        }
        #if DEBUG
        // debugDumpHits disabled for performance - uses expensive Mirror reflection
        // Uncomment for debugging hit field issues:
        // self.debugDumpHits(typedHits, source: "onResults")
        print("[Algolia] onResults: \(typedHits.count) items") // lightweight log only
        #endif
        // Kick off signed-URL prefetch for this page so UI can render private images
        self.prefetchThumbs(for: typedHits)
        if !typedHits.isEmpty {
            // Save generic cache (query + filters)
            let key = self.currentCacheKey()
            self.writeHitsCache(typedHits, for: key)

            // Save the Featured (empty state) feed only when no refinements
            if noQuery && noFacets {
                self.defaultFeedCache.save(typedHits)
            }
        }
    }
}

/// When facets (FilterState) change, decide whether to hit Algolia or show the cached default.
private func wireFilterDrivenSearch() {
    filterState.onChange.subscribe(with: self) { owner, _ in
        Task { @MainActor in
            if owner.shouldShowFeatured {
                owner.searcher?.cancel()
                _ = owner.showCachedDefaultIfAvailable()
            }
            // Otherwise, let connectFilterState trigger a filtered search.
        }
    }
}

/// Perform a first-run preload with retries if needed.
@MainActor
private func kickInitialPreloadIfNeeded() {
    guard !didKickInitialPreload else { return }
    didKickInitialPreload = true

    // If we can show a cached featured feed immediately, do that.
    if showCachedDefaultIfAvailable() { return }

    // Ensure an empty query and first page; rely on connectors to propagate.
    updateQuery("")
    searcher?.request.query.page = 0

    // Perform an initial search now.
    searcher?.search()

    #if DEBUG
    debugLog("initial preload search kicked")
    #endif

    // Two safety-net retries in case the first request races with setup or returns late.
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 800_000_000)
        if self.hitsController.hits.isEmpty {
            #if DEBUG
            self.debugLog("preload retry #1")
            #endif
            self.searcher?.search()
        }
    }
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        if self.hitsController.hits.isEmpty {
            #if DEBUG
            self.debugLog("preload retry #2")
            #endif
            self.searcher?.search()
        }
    }
}

// MARK: - External hooks for the SwiftUI screen

    // MARK: - Navigation (cache-first to avoid duplicate Algolia calls)

    /// Programmatic navigation to a listing by id (used by thumbnail taps or push deep links).
    /// Only handles navigation; ListingDetailHost handles image signing.
    @MainActor
    func openListing(id: String) {
        // If we already have a hit for this id (visible hits, caches), remember it for the detail screen.
        if let known = lookupHitLocally(id: id) {
            lastSelectedHitById[id] = known
        } else {
            // As a fallback, try to find it among currently loaded hits by matching listingIdentifier
            if let h = hitsController.hits.compactMap({ $0 }).first(where: { listingIdentifier(for: $0) == id }) {
                lastSelectedHitById[id] = h
            }
        }
        path.append(ListingRoute.listingID(id))
    }

    /// Programmatic navigation from a hit (prefers `listingID`, falls back to `objectID`).
    /// Caches the hit for instant rendering in detail, then navigates.
    /// Only handles caching and navigation; ListingDetailHost handles image signing.
    @MainActor
    func openListing(from hit: ListingHit) {
        guard let id = listingIdentifier(for: hit) else {
            debugLog("openListing(from:) could not extract id from hit")
            return
        }
        rememberHit(hit)
        path.append(ListingRoute.listingID(id))
    }

    /// Allow external callers (e.g., grid cells) to cache a hit before navigation.
    @MainActor
    func cacheHitBeforeOpen(_ hit: ListingHit) {
        rememberHit(hit)
    }

    /// Backward-compat: older call sites may still call `openListingDetail(_:)`.
    @MainActor
    func openListingDetail(_ hit: ListingHit) {
        openListing(from: hit)
    }

    /// Get a locally cached ListingHit by id (listingID preferred, then objectID).
    /// Used by ListingDetailHost to instantly render detail before network fetch.
    func getCachedListing(by id: String) -> ListingHit? {
        return lookupHitLocally(id: id)
    }

/// Try to find a hit locally by id (listingID preferred, then objectID)
private func lookupHitLocally(id: String) -> ListingHit? {
    if let h = lastSelectedHitById[id] { return h }
    if let h = hitsController.hits.compactMap({ $0 }).first(where: { listingIdentifier(for: $0) == id }) { return h }
    if let cached = defaultFeedCache.load()?.compactMap({ $0 }).first(where: { listingIdentifier(for: $0) == id }) { return cached }
    for entry in hitsCache.values {
        if let h = entry.items.first(where: { listingIdentifier(for: $0) == id }) { return h }
    }
    return nil
}

/// Remembers a hit explicitly in the cache by its identifier.
private func rememberHit(_ hit: ListingHit) {
    if let id = listingIdentifier(for: hit) {
        lastSelectedHitById[id] = hit
    }
}

/// Load a single listing suitable for the detail view. Attempts local caches first, then Algolia.
func loadListingDetail(id: String) async -> ListingHit? {
    // Fast path: anything in-memory
    if let local = lookupHitLocally(id: id) { return local }
    guard let client = client else { return nil }
    let index = client.index(withName: IndexName(rawValue: "LoomPair"))

    // 1) Try as Algolia objectID
    if let obj: ListingHit = try? await index.getObject(withID: ObjectID(rawValue: id)) {
        return obj
    }

    // 2) Try as custom listingID via a 1-hit search
    var q = Query()
    q.hitsPerPage = 1
    q.filters = "listingID:\"\(id)\""
    q.attributesToRetrieve = searcher?.request.query.attributesToRetrieve

    if let res = try? await index.search(query: q),
       let first = res.hits.first,
       let data = try? JSONEncoder().encode(first.object),
       let hit = try? JSONDecoder().decode(ListingHit.self, from: data) {
        return hit
    }
    return nil
}

/// If you later add local caching for a "featured" feed, return true after
/// populating the hits controller and skip the network call.
/// For now, this returns false so the caller knows there is no cached content.
@MainActor
@discardableResult
func showCachedDefaultIfAvailable() -> Bool {
    guard let cached = defaultFeedCache.load(), !cached.isEmpty else { return false }
    // Push cached items directly to the Hits controller so the UI renders immediately
    hitsController.hits = cached
    // Warm image cache for cached results as well
    prefetchThumbs(for: cached)
    #if DEBUG
    debugLog("default feed cache hit: \(cached.count) items")
    #endif
    return true
}

/// Cancel any in-flight Algolia request (useful when the user clears the field).
@MainActor
func cancelOngoingSearchIfAny() {
    searcher?.cancel()
}

/// Central decision point: if there is a query or active facets, search; otherwise cancel and show cache.
@MainActor
func requestSearchOrShowCached() {
    if shouldShowFeatured {
        // We are back to the "Featured" context: avoid network and show locally cached feed.
        searcher?.cancel()
        _ = showCachedDefaultIfAvailable()
    } else {
        // Try cache first for this query+filters
        let key = currentCacheKey()
        if let cached = readHitsCache(for: key) {
            hitsController.hits = cached
            // Warm image cache when serving from memory cache
            prefetchThumbs(for: cached)
            #if DEBUG
            debugLog("cache hit: \(cached.count) items, key=\(key)")
            #endif
            // also fire a background refresh so new listings show up next time
            Task { @MainActor in
                self.searcher?.request.query.page = 0
                self.searcher?.search()
            }
            return
        }
        #if DEBUG
        debugLog("API search start, key=\(key)")
        #endif
        // Otherwise perform network search
        searcher?.search()
    }
}

/// Programmatically trigger a search (e.g., when the UI wants to force-submit).
    @MainActor
    func performSearchNow() {
        requestSearchOrShowCached()
    }

    /// Loads the next page of hits if possible.
    @MainActor
    func loadMoreIfPossible() {
        // Fallback pagination for SDK where pageLoader doesn't expose hasMore/loadNextPage
        guard let searcher = searcher else { return }
        // Increment page and search again; Algolia will return empty when there is nothing more
        let currentPage = searcher.request.query.page ?? 0
        searcher.request.query.page = currentPage + 1
        searcher.search()
    }

// All Firestore/imageSigner/signed URL fetching methods have been removed.
// ListingDetailHost is now responsible for signing images as needed.

    @MainActor
    func search() {
        requestSearchOrShowCached()
    }

/// Update only the textual query term (what the user typed).
/// The SearchBoxConnector will propagate to the searcher and trigger the search.
func updateQuery(_ text: String) {
    // Keep the SearchBox interactor in sync for UI bindings
    searchBoxInteractor.query = text

    // Also update the searcher directly to guarantee the request is updated
    // (ensures programmatic changes propagate even if the connector misses them)
    if let searcher = searcher {
        searcher.request.query.query = text.isEmpty ? nil : text
    }
    // No manual search() here; SearchBoxConnector triggers searches on query updates.
}
}
