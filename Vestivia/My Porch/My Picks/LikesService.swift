//
//  LikesService.swift
//  Exchange
//
//  Created by William Hunsucker on 9/5/25.
//

//
//  LikesService.swift
//  Exchange
//
//  Created by You on 9/5/25.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Centralized likes API (mirrors both user->likes and listing->likes)
enum LikesService {

    // MARK: - Paths (using your FSPath helper)

    /// /users/{likerUid}/likes/{listingId}
    private static func userLikeDoc(likerUid: String, listingId: String) -> DocumentReference {
        FSPath.likes(of: likerUid).document(listingId)
    }

    /// /users/{ownerUid}/listings/{listingId}/likes/{likerUid}
    private static func listingLikeDoc(ownerUid: String, listingId: String, likerUid: String) -> DocumentReference {
        FSPath.listingLikes(owner: ownerUid, listingId: listingId).document(likerUid)
    }

    /// Convenience: current signed-in user UID (throws if missing)
    @inline(__always)
    private static func currentUid() throws -> String {
        if let uid = Auth.auth().currentUser?.uid { return uid }
        throw NSError(domain: "LikesService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
    }

    // MARK: - Public API

    /// Returns true if *current user* has liked this listing.
    static func isLiked(ownerUid: String, listingId: String) async throws -> Bool {
        let likerUid = try currentUid()
        let snap = try await userLikeDoc(likerUid: likerUid, listingId: listingId).getDocument()
        return snap.exists
    }

    /// Atomically sets like/unlike for the *current user* for a listing.
    /// Returns the final liked state (true = liked).
    static func setLiked(_ liked: Bool, ownerUid: String, listingId: String) async throws -> Bool {
        let likerUid = try currentUid()
        let userDoc    = userLikeDoc(likerUid: likerUid, listingId: listingId)
        let listingDoc = listingLikeDoc(ownerUid: ownerUid, listingId: listingId, likerUid: likerUid)

        let batch = FSPath.batch()
        if liked {
            let now = FieldValue.serverTimestamp()
            batch.setData(["ts": now, "ownerUid": ownerUid], forDocument: userDoc, merge: true)
            batch.setData(["ts": now],                         forDocument: listingDoc, merge: true)
        } else {
            batch.deleteDocument(userDoc)
            batch.deleteDocument(listingDoc)
        }
        try await batch.commit()
        // Pin/unpin the listing's primary image in the local cache so liked items stay warm
        // and unliked items can be cleaned up later.
        Task { @MainActor in
            #if DEBUG
            print("[LikesService] \(liked ? "pin" : "unpin") request for listingId=\(listingId)")
            #endif
            NotificationCenter.default.post(
                name: .listingLikePinningRequest,
                object: nil,
                userInfo: [
                    "listingId": listingId,
                    "variant": CFVariant.card.rawValue,
                    "action": liked ? "pin" : "unpin"
                ]
            )
        }
        return liked
    }

    /// Convenient toggle (reads then flips).
    /// Returns the *new* liked state.
    static func toggleLike(ownerUid: String, listingId: String) async throws -> Bool {
        let currently = try await isLiked(ownerUid: ownerUid, listingId: listingId)
        return try await setLiked(!currently, ownerUid: ownerUid, listingId: listingId)
    }

    /// Observe the live like count of a listing via its `/likes` subcollection.
    /// The listener is cheap at small scale and perfect for product pages.
    /// - Returns: a `ListenerRegistration` you should stop when no longer needed.
    @discardableResult
    static func observeLikeCount(ownerUid: String,
                                 listingId: String,
                                 onChange: @escaping (Int) -> Void) -> ListenerRegistration {
        // Listen to the likes subcollection and forward the count
        return FSPath.listingLikes(owner: ownerUid, listingId: listingId)
            .addSnapshotListener { snapshot, error in
                #if DEBUG
                if let error { print("🔴 observeLikeCount error:", error.localizedDescription) }
                #endif
                let n = snapshot?.documents.count ?? 0
                onChange(n)
            }
    }

    /// Back-compat alias for older call sites (use setLiked(_:ownerUid:listingId:) instead)
    @available(*, deprecated, message: "Use setLiked(_:ownerUid:listingId:) instead")
    static func setLike(_ like: Bool, ownerUid: String, listingId: String) async throws -> Bool {
        return try await setLiked(like, ownerUid: ownerUid, listingId: listingId)
    }

    /// One-shot server count using Firestore aggregation.
    static func fetchLikeCount(ownerUid: String, listingId: String) async throws -> Int {
        let query = FSPath.listingLikes(owner: ownerUid, listingId: listingId)
        let aggregate = query.count
        let snap = try await aggregate.getAggregation(source: .server)
        return Int(truncating: snap.count)
    }

    /// Observe whether the *current user* has liked a given listing.
    /// Returns a Firestore listener; if no signed-in user, immediately calls onChange(false) and returns nil.
    @discardableResult
    static func observeUserLike(ownerUid: String,
                                listingId: String,
                                onChange: @escaping (Bool) -> Void) -> ListenerRegistration? {
        guard let likerUid = Auth.auth().currentUser?.uid else {
            DispatchQueue.main.async { onChange(false) }
            return nil
        }
        return userLikeDoc(likerUid: likerUid, listingId: listingId)
            .addSnapshotListener { snap, _ in
                onChange(snap?.exists == true)
            }
    }
}

extension Notification.Name {
    static let listingLikePinningRequest = Notification.Name("ListingLikePinningRequest")
}
