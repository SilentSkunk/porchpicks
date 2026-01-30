//
//  LikeState.swift
//  Exchange
//
//  Created by William Hunsucker on 9/5/25.
//


import Foundation
import Combine
import FirebaseFirestore
@preconcurrency import FirebaseFunctions

/// Observable like state used by both InstantSearchScreen and ListingDetailView
public final class LikeState: ObservableObject {
    public let ownerUid: String
    public let listingId: String

    @Published public var isLiked: Bool = false
    @Published public var likeCount: Int = 0

    private var userListener: ListenerRegistration?
    private var countListener: ListenerRegistration?

    public init(ownerUid: String, listingId: String) {
        self.ownerUid = ownerUid
        self.listingId = listingId
    }

    public func start() {
        guard !ownerUid.isEmpty, !listingId.isEmpty else {
            print("[LikeState] Invalid ownerUid or listingId; skipping listeners")
            return
        }
        // keep listeners in sync with Firestore
        // 1) observe whether current user has liked this listing
        userListener = LikesService.observeUserLike(ownerUid: ownerUid, listingId: listingId) { [weak self] liked in
            self?.isLiked = liked
        }
        // 2) observe aggregate like count for the listing
        countListener = LikesService.observeLikeCount(ownerUid: ownerUid, listingId: listingId) { [weak self] count in
            self?.likeCount = max(0, count)
        }
    }

    public func stop() {
        userListener?.remove(); userListener = nil
        countListener?.remove(); countListener = nil
    }

    /// Toggle with optimistic UI; defers to LikesService
    @MainActor
    public func toggle() {
        guard !ownerUid.isEmpty, !listingId.isEmpty else {
            print("[LikeState] Invalid ownerUid or listingId; cannot toggle")
            return
        }
        Task {
            let next = !isLiked
            do {
                _ = try await LikesService.setLiked(next, ownerUid: ownerUid, listingId: listingId)
                // Optimistic UI
                self.isLiked = next
                self.likeCount = max(0, self.likeCount + (next ? 1 : -1))
            } catch {
                // If you want to revert on failure, uncomment:
                // self.isLiked.toggle()
                // self.likeCount = max(0, self.likeCount + (self.isLiked ? 1 : -1))
                #if DEBUG
                print("[LikeState] toggle error:", error.localizedDescription)
                #endif
            }
        }
    }
}
