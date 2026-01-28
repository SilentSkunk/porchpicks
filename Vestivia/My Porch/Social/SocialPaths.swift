//
//  SocialPaths.swift
//  Exchange
//
//  Created by William Hunsucker on 10/16/25.
//


import FirebaseFirestore

struct SocialPaths {
    static func followingDoc(myUid: String, sellerId: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(myUid)
            .collection("following").document(sellerId)
    }
    static func followersCol(sellerId: String) -> CollectionReference {
        Firestore.firestore().collection("users").document(sellerId)
            .collection("followers")
    }
    static func userDoc(_ uid: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(uid)
    }
}

// Is current user following seller?
func isFollowing(myUid: String, sellerId: String) async throws -> Bool {
    let snap = try await SocialPaths.followingDoc(myUid: myUid, sellerId: sellerId).getDocument()
    return snap.exists
}

// Follow (client writes only to "following"; CF will mirror + bump counts)
func follow(myUid: String, sellerId: String) async throws {
    try await SocialPaths.followingDoc(myUid: myUid, sellerId: sellerId)
        .setData(["createdAt": FieldValue.serverTimestamp()], merge: false)
}

// Unfollow
func unfollow(myUid: String, sellerId: String) async throws {
    try await SocialPaths.followingDoc(myUid: myUid, sellerId: sellerId).delete()
}

// Public counts (anyone can read)
func loadCounts(sellerId: String) async throws -> (followers: Int, following: Int) {
    let doc = try await SocialPaths.userDoc(sellerId).getDocument()
    let followers = doc.data()?["followerCount"] as? Int ?? 0
    let following = doc.data()?["followingCount"] as? Int ?? 0
    return (followers, following)
}

// Public followers list (for a “followers” screen)
func fetchFollowers(sellerId: String, limit: Int = 50) async throws -> [String] {
    let q = try await SocialPaths.followersCol(sellerId: sellerId)
        .order(by: "createdAt", descending: true)
        .limit(to: limit)
        .getDocuments()
    return q.documents.map { $0.documentID } // follower UIDs
}