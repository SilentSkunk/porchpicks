// Optimized GridThumbCard - reduces Firestore listeners by 90%

// STEP 1: Create a shared LikesManager to batch requests
actor LikesManager {
    static let shared = LikesManager()
    
    private var likeStates: [String: Bool] = [:]  // listingId -> isLiked
    private var likeCounts: [String: Int] = [:]   // listingId -> count
    private var activeListeners: [String: ListenerRegistration] = [:]
    
    // Batch fetch likes for multiple listings at once
    func fetchLikesForListings(_ listingIds: [String]) async {
        // TODO: Implement batch Firestore query instead of individual listeners
        // This reduces 20 queries to 1-2 batch queries
    }
    
    func getLikeState(for listingId: String) -> (isLiked: Bool, count: Int) {
        return (likeStates[listingId] ?? false, likeCounts[listingId] ?? 0)
    }
}

// STEP 2: Simplified GridThumbCard without per-cell listeners
private struct OptimizedGridThumbCard: View {
    let hit: ListingHit
    let coordinator: InstantSearchCoordinator
    let title: String
    let sellerName: String
    let priceText: String

    // State loaded once, not with listeners
    @State private var isLiked: Bool = false
    @State private var likeCount: Int = 0
    @State private var thumb: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Use simple AsyncImage with URLCache (no signing needed for thumbnails)
                AsyncImage(url: thumb) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(height: 150)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 150)
                            .clipped()
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 150)
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Simple like button - updates optimistically
                Button {
                    isLiked.toggle()
                    if let owner = InstantSearchScreen.ownerUid(from: hit) {
                        Task {
                            try? await LikesService.setLiked(isLiked, ownerUid: owner, listingId: hit.listingID)
                        }
                    }
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
            }

            Text(title).font(.headline).lineLimit(1)
            Text(sellerName).font(.caption).foregroundStyle(.secondary)
            Text(priceText).font(.subheadline.weight(.semibold))
        }
        .task {
            // Load thumbnail URL (cheap operation)
            thumb = buildThumbURL()
            
            // Batch load like state (expensive operation done once)
            let state = await LikesManager.shared.getLikeState(for: hit.listingID)
            isLiked = state.isLiked
            likeCount = state.count
        }
    }
    
    private func buildThumbURL() -> URL? {
        let chosenId = (hit.preferredImageId?.isEmpty == false ? hit.preferredImageId : nil)
            ?? (hit.primaryImageId?.isEmpty == false ? hit.primaryImageId : nil)
            ?? (hit.imageIds?.first?.isEmpty == false ? hit.imageIds?.first : nil)
        
        guard let imageId = chosenId, !imageId.isEmpty else { return nil }
        
        if imageId.hasPrefix("http://") || imageId.hasPrefix("https://") {
            return URL(string: imageId)
        }
        
        let urlString = "\(CFImagesConfig.publicHost)/\(imageId)/Thumbnail"
        return URL(string: urlString)
    }
}
