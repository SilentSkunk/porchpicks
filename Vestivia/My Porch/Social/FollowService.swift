//
//  FollowService.swift
//  Exchange
//
//  Created by William Hunsucker on 10/16/25.
//


// FollowService.swift
import Foundation
import FirebaseFunctions
import FirebaseFirestore
import FirebaseAuth

final class FollowService {
    static let shared = FollowService()
    private let db = Firestore.firestore()
    private let fx = Functions.functions(region: "us-central1")

    private var me: String? { Auth.auth().currentUser?.uid }

    // Optimistic follow
    @discardableResult
    func follow(targetUid: String) async throws -> Bool {
        _ = try await fx.httpsCallable("followUser").call(["targetUid": targetUid])
        return true
    }

    // Optimistic unfollow
    @discardableResult
    func unfollow(targetUid: String) async throws -> Bool {
        _ = try await fx.httpsCallable("unfollowUser").call(["targetUid": targetUid])
        return true
    }

    // Is the current user following target?
    func isFollowing(targetUid: String) async throws -> Bool {
        guard let me = me else { return false }
        let snap = try await db
            .collection("users")
            .document(me)
            .collection("following")
            .document(targetUid)
            .getDocument()
        return snap.exists
    }

    // Live counts off the user doc (counters maintained by CF)
    func listenCounts(userUid: String, onChange: @escaping (_ followers: Int, _ following: Int) -> Void) -> ListenerRegistration {
        db.collection("users").document(userUid).addSnapshotListener { snap, _ in
            let followers = (snap?.data()?["followerCount"] as? Int) ?? 0
            let following = (snap?.data()?["followingCount"] as? Int) ?? 0
            onChange(followers, following)
        }
    }

    // Count active listings using count() aggregation (sold == false)
    func fetchActiveListingsCount(for userUid: String) async -> Int {
        do {
            let q = db
                .collection("users")
                .document(userUid)
                .collection("listings")
                .whereField("sold", isEqualTo: false)
            let agg = try await q.count.getAggregation(source: AggregateSource.server)
            return Int(agg.count)
        } catch {
            return 0
        }
    }

    // Live profile (username, photoURL) — optional helper
    func listenProfile(userUid: String, onChange: @escaping (_ username: String, _ photoURL: URL?) -> Void) -> ListenerRegistration {
        db.collection("users").document(userUid).addSnapshotListener { snap, _ in
            let uname = (snap?.data()?["username"] as? String) ?? "User"
            let urlStr = (snap?.data()?["photoURL"] as? String) ?? (snap?.data()?["avatarUrl"] as? String)
            let url = urlStr.flatMap { URL(string: $0) }
            onChange(uname, url)
        }
    }
}
