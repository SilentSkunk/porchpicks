
import SwiftUI
import InstantSearch
import InstantSearchSwiftUI
import FirebaseFirestore


// MARK: - Cloudflare Images config for thumbnails (public variant)
private enum CFImagesConfig {
    static let accountHash: String = {
        // Read from Info.plist (key: CF_IMAGES_ACCOUNT_HASH); fallback to the known hash if missing
        (Bundle.main.object(forInfoDictionaryKey: "CF_IMAGES_ACCOUNT_HASH") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        ? (Bundle.main.object(forInfoDictionaryKey: "CF_IMAGES_ACCOUNT_HASH") as! String)
        : "bh7zSZiTTc0igci1WPjT5w"
    }()
    static var publicHost: String { "https://imagedelivery.net/\(accountHash)" }
}
private let CF_IMAGE_HOST = CFImagesConfig.publicHost   // Cloudflare Images delivery base
private let CF_THUMB_VARIANT = "Thumbnail"              // public variant for grid tiles (capital T)


struct InstantSearchScreen: View {
    @ObservedObject var coordinator: InstantSearchCoordinator
    @Binding var selectedTab: AppTab
    @Binding var isPresented: Bool
    var showTabBar: Bool = true

    @State private var hitCount: Int = 0
    @State private var isEditing: Bool = false
    @State private var didInitialLoad: Bool = false
    @State private var initialSearchStarted = false
    @State private var fallbackSearchScheduled = false

    // DEBUG: Track NavigationStack path size
    @State private var lastNavPathCount: Int = 0

    @AppStorage("lastSeenListingsVersion") private var lastSeenListingsVersionStored: Int = 0

    // Recently viewed (persisted as JSON string for portability)
    @AppStorage("recentlyViewedJSON") private var recentlyViewedJSON: String = "[]"
    private let maxRecentViewed = 50
    private var recentlyViewedIDs: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(recentlyViewedJSON.utf8))) ?? []
    }
    private func recordViewed(_ id: String) {
        var arr = recentlyViewedIDs
        // move to front, unique
        if let idx = arr.firstIndex(of: id) { arr.remove(at: idx) }
        arr.insert(id, at: 0)
        if arr.count > maxRecentViewed { arr = Array(arr.prefix(maxRecentViewed)) }
        if let data = try? JSONEncoder().encode(arr), let s = String(data: data, encoding: .utf8) {
            recentlyViewedJSON = s
        }
    }


    // MARK: - Filter bar state
    @State private var showSortSheet = false
    @State private var showCategorySheet = false
    @State private var showBrandSheet = false
    @State private var showSizeSheet = false
    @State private var showColorSheet = false
    @State private var showConditionSheet = false

    @State private var selectedCategory: String? = nil
    @State private var selectedBrand: String? = nil
    @State private var selectedSize: String? = nil
    @State private var selectedColor: String? = nil
    @State private var selectedCondition: String? = nil

    // Grid layout for product cards
    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    // Search debouncing to reduce API calls
    @State private var searchDebounceTask: Task<Void, Never>? = nil

    private var activeFiltersCount: Int {
        [selectedCategory, selectedBrand, selectedSize, selectedColor, selectedCondition]
            .compactMap { $0 }
            .filter { $0 != "All" }
            .count
    }

    // Basic option lists (brands come from centralized list when provided)
    private let categoryOptions = ["All", "Dresses", "Tops", "Bottoms", "Shoes", "Accessories", "Newborn", "Infant", "Toddler", "Boys", "Girls"]
    private let sizeOptions = ["All", "NB", "0-3M", "3-6M", "6-9M", "12M", "2", "4", "6", "8", "10", "S", "M", "L"]
    private let colorOptions = ["All", "White", "Black", "Gray", "Pink", "Blue", "Green", "Yellow", "Red", "Purple", "Brown", "Orange"]
    private let conditionOptions = ["All", "New", "Like New", "Good", "Fair"]

    // Centralized brands injection (pass in from BrandFields)
    var brands: [String] = []

    // MARK: - Helpers
    private var brandOptions: [String] {
        let list = BrandFields().brands
        return list.map { brand in
            brand.name
        }
    }

    private var items: [ListingHit] {
        coordinator.hitsController.hits.compactMap { $0 }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { coordinator.searchBoxController.query },
            set: { newValue in
                coordinator.searchBoxController.query = newValue

                // Cancel any pending debounced search
                searchDebounceTask?.cancel()

                // Clear query triggers instant search (for UX responsiveness)
                if newValue.isEmpty {
                    coordinator.searchBoxController.submit()
                } else {
                    // Debounce non-empty queries by 300ms to reduce API calls
                    searchDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                        if !Task.isCancelled {
                            await MainActor.run {
                                coordinator.searchBoxController.submit()
                            }
                        }
                    }
                }
            }
        )
    }

    // Push current UI selections into Algolia FilterState via the coordinator
    private func updateFiltersFromSelections() {
        // Category
        if let cat = selectedCategory, cat != "All" {
            coordinator.facets.selectCategory(cat)
        } else {
            coordinator.facets.selectCategory(nil)
        }
        // Brand
        if let br = selectedBrand, br != "All" {
            coordinator.facets.selectBrand(br)
        } else {
            coordinator.facets.selectBrand(nil)
        }
        // Size (FacetFilters supports multi-select; we pass 0 or 1 values based on UI)
        if let sz = selectedSize, sz != "All" {
            coordinator.facets.setSizes([sz])
        } else {
            coordinator.facets.setSizes([])
        }
        // Color (multi-select capable as well)
        if let col = selectedColor, col != "All" {
            coordinator.facets.setColors([col])
        } else {
            coordinator.facets.setColors([])
        }
        // Condition
        if let con = selectedCondition, con != "All" {
            coordinator.facets.selectCondition(con)
        } else {
            coordinator.facets.selectCondition(nil)
        }
    }

    // MARK: - Display helpers
    private func displayTitle(for hit: ListingHit) -> String {
        if let description = hit.description, !description.isEmpty { return description }
        if let brand = hit.brand, !brand.isEmpty { return brand }
        return "Untitled"
    }

    private func displayPrice(for hit: ListingHit) -> String {
        if let price = hit.listingPrice, !price.isEmpty { return price }
        if let priceNum = hit.originalPrice, !priceNum.isEmpty { return priceNum }
        return "$—"
    }

    /// Picks the best available image identifier on a hit.
    /// Order: preferredImageId → primaryImageId → first imageIds element.
    private func bestImageId(for hit: ListingHit) -> String? {
        if let s = hit.preferredImageId, !s.isEmpty { return s }
        if let s = hit.primaryImageId, !s.isEmpty { return s }
        if let s = hit.imageIds?.first, !s.isEmpty { return s }
        return nil
    }

    /// Build public Cloudflare Images thumbnail URL from the image id on the hit.
    /// Grid tiles must use the "thumbnail" variant (always public).
    private func thumbURL(for hit: ListingHit) -> URL? {
        // Prefer preferredImageId, fall back to primaryImageId then imageIds.first
        let chosenId = bestImageId(for: hit)

        guard let imageId = chosenId, !imageId.isEmpty else {
            return nil
        }

        // If the field already (incorrectly) contains a full URL, just return it.
        if imageId.hasPrefix("http://") || imageId.hasPrefix("https://") {
            return URL(string: imageId)
        }

        let urlString = "\(CF_IMAGE_HOST)/\(imageId)/\(CF_THUMB_VARIANT)"
        return URL(string: urlString)
    }

    /// Some older records may still carry absolute URLs under `imageURLs`.
    /// Use the first one as a visual fallback if Cloudflare `imageId` is missing or fails.
    private func legacyFallbackURL(for hit: ListingHit) -> URL? {
        guard let first = hit.imageURLs?.first, !first.isEmpty, let url = URL(string: first) else {
            return nil
        }
        return url
    }

    /// DEBUG: Dump a concise summary of what was pulled from Algolia
    private func debugLogPulledHits(context: String = "results") {
        #if DEBUG
        let pulled = coordinator.hitsController.hits.compactMap { $0 }
        print("[IS][\(context)] pulled \(pulled.count) hits")
        for (idx, h) in pulled.prefix(50).enumerated() {
            let id = h.listingID
            let title = displayTitle(for: h)
            let preferred = h.preferredImageId ?? "nil"
            let primary = h.primaryImageId ?? "nil"
            let firstImg = h.imageIds?.first ?? "nil"
            let thumb = thumbURL(for: h)?.absoluteString ?? "nil"
            print("[IS][\(context)] #\(idx) id=\(id) title=\"\(title)\" preferredImageId=\(preferred) primaryImageId=\(primary) firstImageId=\(firstImg) thumb=\(thumb)")
        }
        if pulled.count > 50 {
            print("[IS][\(context)] …truncated \(pulled.count - 50) additional hits")
        }
        #endif
    }
    // Extracts the owner uid from a Firestore path like:
    // users/{uid}/user_listings/{uid}/listings/{listingId}
    private static func ownerUid(from hit: ListingHit) -> String? {
        guard let p = hit.path else { return nil }
        let comps = p.split(separator: "/").map(String.init)
        if let usersIdx = comps.firstIndex(of: "users"), usersIdx + 1 < comps.count {
            return comps[usersIdx + 1]
        }
        return nil
    }

    // MARK: - Views
    @ViewBuilder
    private func FilterBar() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if activeFiltersCount > 0 {
                    FilterChip(text: "Clear") {
                        selectedCategory = nil
                        selectedBrand = nil
                        selectedSize = nil
                        selectedColor = nil
                        selectedCondition = nil
                        coordinator.facets.clearAll()
                        if coordinator.showCachedDefaultIfAvailable() {
                            coordinator.cancelOngoingSearchIfAny()
                        }
                    }
                }

                FilterChip(text: "Sort") { showSortSheet = true }
                FilterChip(text: "Brand", trailing: selectedBrand ?? "All") { showBrandSheet = true }
                FilterChip(text: "Category", trailing: selectedCategory ?? "All") { showCategorySheet = true }
                FilterChip(text: "Size", trailing: selectedSize ?? "All") { showSizeSheet = true }
                FilterChip(text: "Color", trailing: selectedColor ?? "All") { showColorSheet = true }
                FilterChip(text: "Condition", trailing: selectedCondition ?? "All") { showConditionSheet = true }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        // Category sheet
        .sheet(isPresented: $showCategorySheet) {
            SelectionSheet(title: "Category", options: categoryOptions, selection: $selectedCategory) {
                updateFiltersFromSelections()
            }
        }
        // Brand sheet (uses centralized options when supplied)
        .sheet(isPresented: $showBrandSheet) {
            let opts = ["All"] + brandOptions
            SelectionSheet(title: "Brand", options: opts, selection: $selectedBrand) {
                updateFiltersFromSelections()
            }
        }
        // Size sheet
        .sheet(isPresented: $showSizeSheet) {
            SelectionSheet(title: "Size", options: sizeOptions, selection: $selectedSize) {
                updateFiltersFromSelections()
            }
        }
        // Color sheet
        .sheet(isPresented: $showColorSheet) {
            SelectionSheet(title: "Color", options: colorOptions, selection: $selectedColor) {
                updateFiltersFromSelections()
            }
        }
        // Condition sheet
        .sheet(isPresented: $showConditionSheet) {
            SelectionSheet(title: "Condition", options: conditionOptions, selection: $selectedCondition) {
                updateFiltersFromSelections()
            }
        }
        // Sort action sheet (placeholder; real sorting via Algolia replicas)
        .actionSheet(isPresented: $showSortSheet) {
            ActionSheet(title: Text("Sort"), buttons: [
                .default(Text("Relevance")) { /* default - handled by index */ },
                .default(Text("Newest")) { /* requires a replica sorted by createdAt desc */ },
                .cancel()
            ])
        }
    }

    @ViewBuilder
    private func Results() -> some View {
        if items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .imageScale(.large)
                    .font(.system(size: 28))
                    .accessibilityHidden(true)
                Text("No results").font(.headline)
                Text("Pulling the latest listings… if this persists, tap Refresh Feed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    // Manual refresh of the default feed
                    coordinator.facets.clearAll()
                    coordinator.searchBoxController.query = ""
                    coordinator.search()
                    debugLogPulledHits(context: "manual-refresh (pre)")
                } label: {
                    Label("Refresh Feed", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    RecentlyViewedStrip()
                    GridList()
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func RecentlyViewedStrip() -> some View {
        if !recentlyViewedIDs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recently viewed")
                    .font(.headline)
                    .padding(.horizontal, 12)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items.filter { recentlyViewedIDs.contains($0.listingID) }.prefix(10), id: \.listingID) { hit in
                            Group {
                                FallbackAsyncImage(primary: thumbURL(for: hit), fallback: legacyFallbackURL(for: hit), cornerRadius: 12)
                                    .frame(width: 92, height: 92)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                #if DEBUG
                                print("[IS][recently-viewed] tapped id=\(hit.listingID)")
                                #endif
                                recordViewed(hit.listingID)
                                coordinator.openListing(from: hit)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func GridList() -> some View {
        let columns: [GridItem] = [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(items, id: \.listingID) { hit in
                Group {
                    GridThumbCard(
                        hit: hit,
                        coordinator: coordinator,
                        title: displayTitle(for: hit),
                        sellerName: hit.brand ?? "",
                        priceText: displayPrice(for: hit)
                    )
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    #if DEBUG
                    print("[IS][grid] tapped id=\(hit.listingID)")
                    #endif
                    recordViewed(hit.listingID)
                    coordinator.openListing(from: hit)
                }
                .padding(.vertical, 8)
            }
            if items.isEmpty == false {
                Text("End of listings")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 24)
    }

// MARK: - GridThumbCard for grid tiles with signed Thumbnail URL
// PERFORMANCE: Firestore listeners removed to prevent 40 listeners for 20 items
// Like status is now checked on-demand when user taps the heart or views detail
private struct GridThumbCard: View {
    let hit: ListingHit
    let coordinator: InstantSearchCoordinator
    let title: String
    let sellerName: String
    let priceText: String

    @State private var thumb: URL? = nil
    @State private var isLiked: Bool = false
    @State private var likeCount: Int = 0
    @State private var isLoadingLike: Bool = false

    init(hit: ListingHit, coordinator: InstantSearchCoordinator, title: String, sellerName: String, priceText: String) {
        self.hit = hit
        self.coordinator = coordinator
        self.title = title
        self.sellerName = sellerName
        self.priceText = priceText
    }

    private var fallbackURL: URL? {
        if let s = hit.imageURLs?.first, !s.isEmpty, let u = URL(string: s) {
            return u
        }
        return nil
    }

    // Helper for building the thumbnail URL
    private func buildThumbURL() -> URL? {
        // Prefer preferredImageId → primaryImageId → first imageIds element
        let chosenId = (hit.preferredImageId?.isEmpty == false ? hit.preferredImageId : nil)
            ?? (hit.primaryImageId?.isEmpty == false ? hit.primaryImageId : nil)
            ?? (hit.imageIds?.first?.isEmpty == false ? hit.imageIds?.first : nil)

        guard let imageId = chosenId, !imageId.isEmpty else {
            return nil
        }

        // If the field already contains a full URL, just return it.
        if imageId.hasPrefix("http://") || imageId.hasPrefix("https://") {
            return URL(string: imageId)
        }

        let urlString = "\(CF_IMAGE_HOST)/\(imageId)/\(CF_THUMB_VARIANT)"
        return URL(string: urlString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                FallbackAsyncImage(primary: thumb, fallback: fallbackURL)

                Button {
                    // Toggle like via service (async)
                    if let owner = InstantSearchScreen.ownerUid(from: hit) {
                        Task {
                            do {
                                _ = try await LikesService.setLiked(!isLiked, ownerUid: owner, listingId: hit.listingID)
                            } catch {
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .imageScale(.medium)
                        if likeCount > 0 {
                            Text("\(likeCount)")
                                .font(.caption2).bold()
                        }
                    }
                    .padding(8)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .padding(8)
                }
                .buttonStyle(.plain)
            }

            Text(title)
                .font(.headline)
                .lineLimit(1)

            Text(sellerName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(priceText)
                .font(.subheadline.weight(.semibold))
        }
        .padding(3)
        .task {
            // PERFORMANCE: Removed per-cell Firestore listeners (was creating 40 listeners for 20 items)
            // Like status is fetched once on appearance, not via real-time listener
            // Build public Cloudflare Images URL for the Thumbnail variant (public)
            let u = buildThumbURL() ?? fallbackURL
            thumb = u

            // One-time fetch of like status (non-blocking, no listener)
            if let owner = InstantSearchScreen.ownerUid(from: hit) {
                Task.detached(priority: .low) {
                    do {
                        let liked = try await LikesService.isLiked(ownerUid: owner, listingId: hit.listingID)
                        await MainActor.run {
                            self.isLiked = liked
                        }
                    } catch {
                        // Silently ignore - like status is not critical for grid display
                    }
                }
            }
        }
    }
}

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // Top bar: search field
                    HStack(spacing: 12) {
                        // Use existing SearchBar but embed in a rounded background
                        SearchBar(text: queryBinding, isEditing: $isEditing)
                            .onSubmit { coordinator.searchBoxController.submit() }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    FilterBar()

                    Results()
                }
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Open a quick entry point into filters (brand sheet for now)
                        showBrandSheet = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Filters")
                }
            }
            .navigationDestination(for: ListingRoute.self) { route in
                switch route {
                case .listingID(let id):
                    if let hit = coordinator.hitsController.hits.first(where: { $0?.listingID == id }) {
                        ListingDetailHost(hit: hit!)
                    } else {
                        // Fallback if not in cache (fetch detail by id)
                        ListingDetailContainer(listingId: id)
                    }
                }
            }
            .onChange(of: coordinator.path.count) { newCount in
                lastNavPathCount = newCount
            }
            // Accept programmatic search requests from Home (push-to-Shop)
            .onReceive(NotificationCenter.default.publisher(for: .shopSearchRequested)) { note in
                if let q = note.object as? String {
                    coordinator.searchBoxController.query = q
                    coordinator.searchBoxController.submit()
                }
            }
            // When the screen appears, reflect any pre-selected filters and show cached default feed if available
            .onAppear {
                // Initialize nav debug counter
                lastNavPathCount = coordinator.path.count
                // Run initial load exactly once; avoid triggering multiple searches as the view refreshes
                guard !initialSearchStarted else { return }
                initialSearchStarted = true

                // Start clean and **always** kick off a fresh network search (cache is secondary)
                coordinator.cancelOngoingSearchIfAny()
                coordinator.facets.clearAll()
                coordinator.searchBoxController.query = ""
                coordinator.search()
                // Optional: still perform a lightweight version probe to opportunistically refresh later

                // Safety net: two retries if we still have 0 hits
                func hitsCount() -> Int { coordinator.hitsController.hits.compactMap { $0 }.count }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if hitsCount() == 0 {
                        coordinator.searchBoxController.query = "" // ensure blank query
                        coordinator.search()
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    if hitsCount() == 0 {
                        coordinator.searchBoxController.query = ""
                        coordinator.facets.clearAll()
                        coordinator.search()
                    }
                }
                #if DEBUG
                print("[IS][onAppear] initiating fresh search for default feed")
                #endif
            }
            .onChange(of: coordinator.hitsController.hits.compactMap { $0 }.count) { _ in
                debugLogPulledHits(context: "onChange")
            }
            .safeAreaInset(edge: .bottom) {
                // Reserve space for the global tab bar without drawing a white band over content
                Color.clear.frame(height: 80)
            }
        }
        .environmentObject(coordinator)
    }
}

private struct Badge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

private struct FilterChip: View {
    let text: String
    var trailing: String? = nil
    var isPrimary: Bool = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(text)
                if let trailing {
                    Text(trailing)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
            .overlay(Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct SelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let options: [String]
    @Binding var selection: String?
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(options, id: \.self) { opt in
                    OptionRow(title: opt, selected: selection == opt)
                        .onTapGesture {
                            if selection == opt {
                                selection = nil
                            } else {
                                selection = opt
                            }
                        }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { selection = nil; onDone(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(); dismiss() }
                }
            }
        }
    }
}

private struct OptionRow: View {
    let title: String
    let selected: Bool
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if selected {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Card & Seller Header
private struct FallbackAsyncImage: View {
    let primary: URL?
    let fallback: URL?
    var cornerRadius: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.systemBackground))

                Group {
                    if let primary {
                        AsyncImage(url: primary) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            case .failure:
                                fallbackView
                            case .empty:
                                placeholder
                            @unknown default:
                                placeholder
                            }
                        }
                    } else {
                        fallbackView
                    }
                }
                .frame(width: size.width, height: size.width) // enforce square content
                .clipped()
            }
            .frame(width: size.width, height: size.width) // enforce square tile
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private var fallbackView: some View {
        if let fallback {
            AsyncImage(url: fallback) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    // Show placeholder and log the failure
                    placeholder
                case .empty:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color(.systemGray6))
            .overlay(
                Image(systemName: "photo")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            )
    }
}

private struct ProductCard: View {
    let imageURL: URL?
    let fallbackURL: URL?
    let title: String
    let sellerName: String
    let priceText: String
    @State private var isLiked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                FallbackAsyncImage(primary: imageURL, fallback: fallbackURL)

                Button { isLiked.toggle() } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .imageScale(.medium)
                        .padding(8)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                        .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isLiked ? "Remove from likes" : "Add to likes")
            }

            Text(title)
                .font(.headline)
                .lineLimit(1)

            Text(sellerName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(priceText)
                .font(.subheadline.weight(.semibold))
        }
        .padding(3)
    }
}

private struct SellerHeaderRow: View {
    let logoURL: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: logoURL)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: Color(.systemGray6)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.blue)
                        .imageScale(.small)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
        }
    }
}

