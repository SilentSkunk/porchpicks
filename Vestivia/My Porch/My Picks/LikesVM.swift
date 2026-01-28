//
//  LikesVM.swift
//  Exchange
//
//  Created by William Hunsucker on 10/5/25.
//

import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class LikesVM: ObservableObject {
    @Published var items: [ListingSummary] = []
    @Published var heroURLById: [String: URL] = [:]   // listingId -> signed hero URL
    private var heroExpById: [String: TimeInterval] = [:] // UNIX seconds

    private let uid: String
    private let db = Firestore.firestore()
    private var likesListener: ListenerRegistration?

    private var likedIDs: [String] = []
    private var summaries: [String: ListingSummary] = [:] // keyed by listingId

    // Disk cache for hero URLs (per-user small JSON file)
    private var imagesCacheFileURL: URL {
        let fm = FileManager.default
        let dir = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let folder = dir.appendingPathComponent("LikesImageCache", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("likes_images_\(uid).json")
    }

    private struct _DiskImageCacheEntry: Codable { let url: String; let exp: TimeInterval? }
    private func loadImagesCacheFromDisk() {
        do {
            let data = try Data(contentsOf: imagesCacheFileURL)
            let decoded = try JSONDecoder().decode([String: _DiskImageCacheEntry].self, from: data)
            var map: [String: URL] = [:]
            var exp: [String: TimeInterval] = [:]
            for (id, e) in decoded {
                if let u = URL(string: e.url) {
                    map[id] = u
                    if let t = e.exp { exp[id] = t }
                }
            }
            self.heroURLById = map
            self.heroExpById = exp
            #if DEBUG
            print("[LikesVM] loaded hero cache entries:", map.count)
            #endif
        } catch { /* first run / no cache is fine */ }
    }

    private func saveImagesCacheToDisk() {
        var out: [String: _DiskImageCacheEntry] = [:]
        for (id, url) in heroURLById {
            out[id] = _DiskImageCacheEntry(url: url.absoluteString, exp: heroExpById[id])
        }
        do {
            let data = try JSONEncoder().encode(out)
            try data.write(to: imagesCacheFileURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("[LikesVM] save hero cache error:", error)
            #endif
        }
    }

    init(uid: String) {
        self.uid = uid
    }

    func start() {
        stop()

        // Hydrate hero image URLs from our small disk cache (if present)
        loadImagesCacheFromDisk()

        // 1) Cache-first paint
        if let cache = LikesCache.load(uid: uid) {
            self.likedIDs = cache.likedIDs
            self.summaries = cache.summaries
            self.items = likedIDs.compactMap { summaries[$0] }
            #if DEBUG
            print("[LikesVM] cache-first paint: items=\(self.items.count), heroURLs=\(self.heroURLById.count)")
            #endif
        }

        // 2) Live: listen to likes subcollection
        likesListener = db.collection("users")
            .document(uid)
            .collection("likes")
            .order(by: FieldPath.documentID())
            .addSnapshotListener { [weak self] snap, err in
                Task { @MainActor in
                    guard let self else { return }
                    if let err { print("[LikesVM] likes listen error:", err); self.items = []; return }
                    let docs = snap?.documents ?? []
                    
                    // Build (ownerUid, listingId) pairs from like docs
                    let pairs: [(ownerUid: String, listingId: String)] = docs.compactMap { d in
                        let data = d.data()
                        guard let ownerUid = data["ownerUid"] as? String else { return nil }
                        let listingId = (data["listingId"] as? String) ?? d.documentID
                        return (ownerUid, listingId)
                    }
                    
                    // Short-circuit if nothing liked
                    guard !pairs.isEmpty else {
                        self.likedIDs = []
                        self.summaries = [:]
                        self.items = []
                        self.heroURLById = [:]
                        self.heroExpById = [:]
                        LikesCache.save(uid: self.uid, likedIDs: [], summaries: [:])
                        self.saveImagesCacheToDisk()
                        return
                    }
                    
                    self.likedIDs = pairs.map { $0.listingId }
                    
                    // Fetch all listing docs in parallel from their owners' subcollections
                    Task {
                        var dict: [String: ListingSummary] = [:]
                        await withTaskGroup(of: (String, ListingSummary?).self) { group in
                            for pair in pairs {
                                group.addTask {
                                    do {
                                        let snap = try await self.db
                                            .collection("users").document(pair.ownerUid)
                                            .collection("listings").document(pair.listingId)
                                            .getDocument()
                                        if snap.exists {
                                            let summary = ListingSummary.from(snap)
                                            return (pair.listingId, summary)
                                        }
                                    } catch {
                                        print("[LikesVM] fetch listing error:", error)
                                    }
                                    return (pair.listingId, nil)
                                }
                            }
                            
                            for await (id, summary) in group {
                                if let s = summary { dict[id] = s }
                            }
                        }
                        
                        await MainActor.run {
                            self.summaries = dict
                            self.items = self.likedIDs.compactMap { dict[$0] }
                            LikesCache.save(uid: self.uid, likedIDs: self.likedIDs, summaries: dict)
                            self.saveImagesCacheToDisk()
                        }
                    }
                }
            }
    }

    func stop() {
        likesListener?.remove()
        likesListener = nil
    }

    // Optional: pull-to-refresh
    func refreshNow() async {
        // Force a one-shot refetch using the current likedIDs (no need to rebuild listeners)
        let chunks: [[String]] = stride(from: 0, to: likedIDs.count, by: 10).map {
            Array(likedIDs[$0..<min($0 + 10, likedIDs.count)])
        }
        var dict = summaries
        for chunk in chunks {
            do {
                let snap = try await db.collectionGroup("listings")
                    .whereField("id", in: chunk)
                    .getDocuments()
                for doc in snap.documents {
                    let summary = ListingSummary.from(doc)
                    dict[summary.id] = summary
                }
            } catch {
                print("[LikesVM] refresh error:", error)
            }
        }
        summaries = dict
        items = likedIDs.compactMap { dict[$0] }
        LikesCache.save(uid: uid, likedIDs: likedIDs, summaries: summaries)
    }

    /// Return a cached (potentially signed) hero URL for a listing if available and not expired.
    func cachedHeroURL(for listingId: String) -> URL? {
        if let exp = heroExpById[listingId], exp > 0 {
            let now = Date().timeIntervalSince1970
            if now > exp { return nil } // expired; caller may choose to re-sign
        }
        return heroURLById[listingId]
    }

    /// Save/update a hero URL (optionally with an expiration epoch) into the Likes image cache.
    func setCachedHeroURL(_ url: URL, for listingId: String, exp: TimeInterval? = nil) {
        heroURLById[listingId] = url
        if let e = exp { heroExpById[listingId] = e }
        saveImagesCacheToDisk()
    }
}
