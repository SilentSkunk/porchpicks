//
//  ListingSummary.swift
//  Exchange
//
//  Created by William Hunsucker on 10/3/25.
//

import Foundation
import FirebaseFirestore

// MARK: - Configure this to match your Cloudflare Images account
private let CLOUDFLARE_ACCOUNT_HASH = "bh7zSZiTTc0igci1WPjT5w" // seen in your logs
private func cloudflareThumbURL(for imageId: String) -> String {
    "https://imagedelivery.net/\(CLOUDFLARE_ACCOUNT_HASH)/\(imageId)/Thumbnail"
}

// MARK: - Lightweight row model
public struct ListingSummary: Identifiable, Equatable, Codable {
    public let id: String            // Firestore docID == listingID
    public let title: String         // from "description" (your field)
    public let thumbnailURL: String? // built from imageIds/primaryImageId
    public let updatedAt: Date?      // from "lastmodified" (ms) if present

    public init(id: String, title: String, thumbnailURL: String?, updatedAt: Date?) {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.updatedAt = updatedAt
    }
}

public extension ListingSummary {
    static func from(_ doc: DocumentSnapshot) -> ListingSummary {
        let data = doc.data() ?? [:]
        let title = (data["description"] as? String) ?? "Item"
        let imageIds = (data["imageIds"] as? [String]) ?? []
        let primary = (data["primaryImageId"] as? String) ?? imageIds.first
        let thumbURL = primary.map { cloudflareThumbURL(for: $0) }
        let updatedAt: Date? = {
            if let ms = data["lastmodified"] as? Double { return Date(timeIntervalSince1970: ms / 1000.0) }
            if let sec = data["createdAt"] as? Double { return Date(timeIntervalSince1970: sec) }
            return nil
        }()
        return ListingSummary(
            id: doc.documentID,
            title: title,
            thumbnailURL: thumbURL,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Repo protocol
public protocol PorchRepository {
    @discardableResult
    func listenForSale(uid: String,
                       onChange: @escaping ([ListingSummary]) -> Void,
                       onError: @escaping (Error) -> Void) -> ListenerRegistration

    @discardableResult
    func listenLikes(uid: String,
                     onChange: @escaping ([ListingSummary]) -> Void,
                     onError: @escaping (Error) -> Void) -> ListenerRegistration

    func loadCache(uid: String, key: String) -> [ListingSummary]
    func saveCache(uid: String, key: String, items: [ListingSummary])
}

// MARK: - Firestore + simple JSON cache
public final class FirestorePorchRepository: PorchRepository {
    public init() {}
    private let db = Firestore.firestore()

    // ---------- JSON cache ----------
    private func cacheURL(uid: String, key: String) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("porchcache_\(uid)_\(key).json")
    }
    public func loadCache(uid: String, key: String) -> [ListingSummary] {
        let url = cacheURL(uid: uid, key: key)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ListingSummary].self, from: data)) ?? []
    }
    public func saveCache(uid: String, key: String, items: [ListingSummary]) {
        let url = cacheURL(uid: uid, key: key)
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: url, options: .atomic) }
    }

    // ---------- Mapping helpers ----------
    private func mapDoc(_ doc: DocumentSnapshot) -> ListingSummary {
        return ListingSummary.from(doc)
    }

    // ---------- Listeners ----------
    // On My Porch (for sale) — your schema sets "sold": false
    @discardableResult
    public func listenForSale(uid: String,
                              onChange: @escaping ([ListingSummary]) -> Void,
                              onError: @escaping (Error) -> Void) -> ListenerRegistration {
        return db.collection("users").document(uid).collection("listings")
            .whereField("sold", isEqualTo: false)
            .order(by: "lastmodified", descending: true)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                if let err = err { onError(err); return }
                let items = snap?.documents.map(self.mapDoc) ?? []
                onChange(items)
            }
    }

    // My Picks (likes) — hydrates liked listingIDs via collection group
    @discardableResult
    public func listenLikes(uid: String,
                            onChange: @escaping ([ListingSummary]) -> Void,
                            onError: @escaping (Error) -> Void) -> ListenerRegistration {
        // This assumes: users/{uid}/likes/{autoId} with field "listingId"
        // If your LikeService uses a different path/key, tell me and I’ll tweak it.
        let likesRef = db.collection("users").document(uid).collection("likes")
        return likesRef.addSnapshotListener { [weak self] snap, err in
            guard let self else { return }
            if let err = err { onError(err); return }

            let ids: [String] = snap?.documents.compactMap { $0.data()["listingId"] as? String } ?? []
            guard !ids.isEmpty else { onChange([]); return }

            // Firestore 'in' queries allow up to 10 IDs per request
            let chunks = stride(from: 0, to: ids.count, by: 10).map { Array(ids[$0..<min($0+10, ids.count)]) }

            let group = DispatchGroup()
            let syncQueue = DispatchQueue(label: "likes.hydrate.sync")
            var collected: [ListingSummary] = []

            for chunk in chunks {
                group.enter()
                self.db.collectionGroup("listings")
                    .whereField(FieldPath.documentID(), in: chunk)
                    .getDocuments { snap, _ in
                        let mapped = (snap?.documents ?? []).map(self.mapDoc)
                        syncQueue.async {
                            collected.append(contentsOf: mapped)
                            group.leave()
                        }
                    }
            }
            group.notify(queue: .main) {
                let sorted = collected.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
                onChange(sorted)
            }
        }
    }
}

// MARK: - ViewModels (cache-first → live)

@MainActor
public final class ForSaleVM: ObservableObject {
    @Published public private(set) var items: [ListingSummary] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: String?

    private var listener: ListenerRegistration?
    private let uid: String
    private let repo: PorchRepository
    private let cacheKey = "forSale"

    public init(uid: String, repo: PorchRepository = FirestorePorchRepository()) {
        self.uid = uid; self.repo = repo
    }

    public func start() {
        if items.isEmpty { items = repo.loadCache(uid: uid, key: cacheKey) }
        guard listener == nil else { return }
        isLoading = true
        listener = repo.listenForSale(uid: uid, onChange: { [weak self] newItems in
            guard let self else { return }
            self.items = newItems
            self.repo.saveCache(uid: self.uid, key: self.cacheKey, items: newItems)
            self.isLoading = false
        }, onError: { [weak self] err in
            self?.error = err.localizedDescription; self?.isLoading = false
        })
    }

    public func stop() { listener?.remove(); listener = nil }
}

@MainActor
public final class MyPicksVM: ObservableObject {
    @Published public private(set) var items: [ListingSummary] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: String?

    private var listener: ListenerRegistration?
    private let uid: String
    private let repo: PorchRepository
    private let cacheKey = "likes"

    public init(uid: String, repo: PorchRepository = FirestorePorchRepository()) {
        self.uid = uid; self.repo = repo
    }

    public func start() {
        if items.isEmpty { items = repo.loadCache(uid: uid, key: cacheKey) }
        guard listener == nil else { return }
        isLoading = true
        listener = repo.listenLikes(uid: uid, onChange: { [weak self] newItems in
            guard let self else { return }
            self.items = newItems
            self.repo.saveCache(uid: self.uid, key: self.cacheKey, items: newItems)
            self.isLoading = false
        }, onError: { [weak self] err in
            self?.error = err.localizedDescription; self?.isLoading = false
        })
    }

    public func stop() { listener?.remove(); listener = nil }
}
