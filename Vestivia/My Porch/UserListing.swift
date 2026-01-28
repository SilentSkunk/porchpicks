//
//  UserListing.swift
//  Exchange
//
//  Created by William Hunsucker on 8/26/25.
//

//
//  UserListingsStore.swift
//  Vestivia
//
//  Firestore-only listings for a single user, with disk+memory cache.
//  - Instant load from disk cache
//  - Optional realtime listener to keep cache fresh
//  - Manual refresh when you want (e.g., pull-to-refresh)
//

import Foundation
import Combine
import FirebaseFirestore

// MARK: - Model

public struct UserListing: Codable, Identifiable, Equatable {
    public var id: String?                   // Firestore docID
    public var listingID: String?            // business ID, may equal docID
    public var userId: String
    public var brand: String?
    public var category: String?
    public var description: String?
    public var listingPrice: String?
    public var originalPrice: String?
    public var size: String?
    public var color: String?
    public var imageURLs: [String]?
    public var createdAt: Double?            // seconds since epoch
    public var lastmodified: Double?
    public var sold: Bool?                   // <— include if you store sold status

    public var stableID: String { listingID ?? id ?? UUID().uuidString }
}

// MARK: - Store

public final class UserListingsStore: ObservableObject {

    // Public, UI-bindable
    @Published public private(set) var items: [UserListing] = []
    @Published public private(set) var isListening: Bool = false

    // Config
    public let userId: String
    public var hideSold: Bool = true        // filter out sold items by default
    public var pageSize: Int = 50           // Firestore page size for manual refresh

    // Firestore
    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration? = nil

    // Cache
    private let memoryCache = NSCache<NSString, NSData>()
    private let cacheURL: URL

    // Paging (when using manual refresh with pages)
    private var lastSnapshot: DocumentSnapshot? = nil

    // MARK: - Init

    public init(userId: String, cacheFolderName: String = "UserListingsCache") {
        self.userId = userId

        // Prepare disk cache URL: ~/Library/Caches/UserListingsCache/<userId>.json
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent(cacheFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        self.cacheURL = folder.appendingPathComponent("\(userId).json")
    }

    deinit { stopListening() }

    // MARK: - Public API

    /// Load from cache immediately (memory/disk). Does not touch network.
    public func loadFromCache() {
        // Memory first
        let key = cacheURL.path as NSString
        if let data = memoryCache.object(forKey: key) as Data?,
           let decoded = try? JSONDecoder().decode([UserListing].self, from: data) {
            self.items = filtered(decoded)
            return
        }

        // Disk next
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([UserListing].self, from: data) {
            self.memoryCache.setObject(data as NSData, forKey: key, cost: data.count)
            self.items = filtered(decoded)
            return
        }

        // No cache → empty list
        self.items = []
    }

    /// Start a realtime Firestore listener that keeps the cache up to date.
    /// Call `stopListening()` when leaving the screen to stop traffic.
    public func startListening() {
        guard listener == nil else { return }
        let query = baseQuery()
        listener = query.addSnapshotListener { [weak self] snap, error in
            guard let self = self else { return }
            if let error = error {
                print("⚠️ UserListings listener error:", error)
                return
            }
            guard let docs = snap?.documents else { return }

            var next: [UserListing] = []
            next.reserveCapacity(docs.count)
            for doc in docs {
                if let item = parse(doc) {
                    next.append(item)
                }
            }

            // Sort newest first by createdAt
            next.sort(by: { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) })

            self.writeCache(next)
            self.items = self.filtered(next)
        }
        isListening = true
    }

    /// Stop the realtime listener.
    public func stopListening() {
        listener?.remove()
        listener = nil
        isListening = false
    }

    /// Manually refresh (one-shot fetch, no listener). Resets paging.
    public func refresh() async {
        lastSnapshot = nil
        await fetchNextPageAndReplace()
    }

    /// Fetch next page and append (one-shot paging, no listener).
    public func fetchNextPage() async {
        await fetchNextPageAndAppend()
    }

    /// Mark a listing sold (or unsold) and persist to Firestore.
    /// Listener (if active) will reflect this change automatically.
    /// You may be using listingID as the docID. If not, keep a mapping or query by field.
    /// Here we search by field `listingID` in users/{uid}/listings.
    public func setSold(listingID: String, sold: Bool) async throws {
        // You may be using listingID as the docID. If not, keep a mapping or query by field.
        // Here we search by field `listingID` in users/{uid}/listings.
        let col = db.collection("users").document(userId).collection("listings")
        let qs = try await col.whereField("listingID", isEqualTo: listingID).limit(to: 1).getDocuments()
        guard let doc = qs.documents.first else { return }
        try await doc.reference.setData(["sold": sold, "lastmodified": Date().timeIntervalSince1970 * 1000], merge: true)
    }

    // MARK: - Internals

    private func parse(_ doc: DocumentSnapshot) -> UserListing? {
        guard let d = doc.data() else { return nil }

        // createdAt can be Double seconds or Firestore Timestamp
        var createdAt: Double? = nil
        if let v = d["createdAt"] as? Double {
            createdAt = v
        } else if let ts = d["createdAt"] as? Timestamp {
            createdAt = ts.dateValue().timeIntervalSince1970
        }

        // lastmodified can be Double ms or Firestore Timestamp
        var lastmodified: Double? = nil
        if let v = d["lastmodified"] as? Double {
            lastmodified = v
        } else if let ts = d["lastmodified"] as? Timestamp {
            lastmodified = ts.dateValue().timeIntervalSince1970 * 1000
        } else if let num = d["lastmodified"] as? NSNumber {
            lastmodified = num.doubleValue
        }

        // imageURLs: best‑effort cast
        var imageURLs: [String]? = nil
        if let arr = d["imageURLs"] as? [String] {
            imageURLs = arr
        } else if let arr = d["imageURLs"] as? [Any] {
            imageURLs = arr.compactMap { $0 as? String }
        }

        return UserListing(
            id: doc.documentID,
            listingID: (d["listingID"] as? String) ?? doc.documentID,
            userId: (d["userId"] as? String) ?? self.userId,
            brand: d["brand"] as? String,
            category: d["category"] as? String,
            description: d["description"] as? String,
            listingPrice: d["listingPrice"] as? String,
            originalPrice: d["originalPrice"] as? String,
            size: d["size"] as? String,
            color: d["color"] as? String,
            imageURLs: imageURLs,
            createdAt: createdAt,
            lastmodified: lastmodified,
            sold: d["sold"] as? Bool
        )
    }

    private func baseQuery() -> Query {
        // Step 3: listings moved under users/{uid}/listings
        return db.collection("users")
            .document(userId)
            .collection("listings")
            .order(by: "createdAt", descending: true)
    }

    private func filtered(_ list: [UserListing]) -> [UserListing] {
        hideSold ? list.filter { ($0.sold ?? false) == false } : list
    }

    private func writeCache(_ list: [UserListing]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(list) else { return }
        let key = cacheURL.path as NSString
        memoryCache.setObject(data as NSData, forKey: key, cost: data.count)
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func fetchQuery(limit: Int, after: DocumentSnapshot?) async throws -> QuerySnapshot {
        var q = baseQuery().limit(to: limit)
        if let after { q = q.start(afterDocument: after) }
        return try await q.getDocuments()
    }

    @MainActor
    private func fetchNextPageAndReplace() async {
        do {
            let snap = try await fetchQuery(limit: pageSize, after: nil)
            lastSnapshot = snap.documents.last

            var next: [UserListing] = []
            next.reserveCapacity(snap.documents.count)
            for doc in snap.documents {
                if let item = parse(doc) {
                    next.append(item)
                }
            }
            next.sort(by: { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) })

            writeCache(next)
            self.items = filtered(next)
        } catch {
            print("⚠️ UserListings refresh error:", error)
        }
    }

    @MainActor
    private func fetchNextPageAndAppend() async {
        do {
            let snap = try await fetchQuery(limit: pageSize, after: lastSnapshot)
            lastSnapshot = snap.documents.last

            var add: [UserListing] = []
            add.reserveCapacity(snap.documents.count)
            for doc in snap.documents {
                if let item = parse(doc) {
                    add.append(item)
                }
            }

            var merged = items + add
            // Deduplicate by stableID
            var seen = Set<String>()
            merged = merged.filter { seen.insert($0.stableID).inserted }

            writeCache(merged)
            self.items = filtered(merged)
        } catch {
            print("⚠️ UserListings paging error:", error)
        }
    }
}
