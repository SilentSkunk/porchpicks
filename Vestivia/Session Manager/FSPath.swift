//
//  FSPath.swift
//  Exchange
//
//  Created by William Hunsucker on 9/5/25.
//


import FirebaseFirestore

enum FSPath {
    private static var db: Firestore {
        Firestore.firestore()
    }

    static func batch() -> WriteBatch {
        db.batch()
    }

    // /users
    static var users: CollectionReference { db.collection("users") }

    // /users/{uid}
    static func user(_ uid: String) -> DocumentReference {
        users.document(uid)
    }

    // /users/{uid}/listings
    static func listings(of uid: String) -> CollectionReference {
        user(uid).collection("listings")
    }

    // /users/{uid}/listings/{listingId}
    static func listing(of uid: String, id listingId: String) -> DocumentReference {
        listings(of: uid).document(listingId)
    }

    // /users/{uid}/likes/{listingId}
    static func likes(of uid: String) -> CollectionReference {
        user(uid).collection("likes")
    }

    // /users/{owner}/listings/{listing}/likes/{uid}
    static func listingLikes(owner ownerUid: String, listingId: String) -> CollectionReference {
        listing(of: ownerUid, id: listingId).collection("likes")
    }

    // /users/{uid}/likes/{listingId}
    static func userLikeDoc(uid: String, listingId: String) -> DocumentReference {
        likes(of: uid).document(listingId)
    }

    // /users/{owner}/listings/{listingId}/likes/{likerUid}
    static func listingLikeDoc(ownerUid: String, listingId: String, likerUid: String) -> DocumentReference {
        listingLikes(owner: ownerUid, listingId: listingId).document(likerUid)
    }
}
