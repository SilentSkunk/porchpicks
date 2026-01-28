// ListingCache.swift
import Foundation
import UIKit

// Tune here
struct ListingCachePolicy {
    static var viewTTL: TimeInterval = 24 * 60 * 60  // 24h for non-liked
}

final class ListingRecordCache {
    static let shared = ListingRecordCache()

    private struct Entry {
        var hit: ListingHit
        var expiry: TimeInterval?   // nil = pinned (liked)
        var isLiked: Bool
    }

    private var map: [String: Entry] = [:]  // key = listingId
    private let lock = NSLock()

    // MARK: Get
    func get(_ id: String) -> ListingHit? {
        lock.lock(); defer { lock.unlock() }
        guard var e = map[id] else { return nil }
        if let exp = e.expiry, Date().timeIntervalSince1970 >= exp {
            map[id] = nil
            return nil
        }
        // refresh-on-read for viewed entries (optional)
        if !e.isLiked, e.expiry != nil {
            e.expiry = Date().timeIntervalSince1970 + ListingCachePolicy.viewTTL
            map[id] = e
        }
        return e.hit
    }

    // MARK: Set / Promote / Demote
    func putViewed(_ hit: ListingHit) {
        lock.lock(); defer { lock.unlock() }
        map[hit.listingID] = Entry(hit: hit,
                                   expiry: Date().timeIntervalSince1970 + ListingCachePolicy.viewTTL,
                                   isLiked: false)
    }

    func promoteToLiked(_ hit: ListingHit) {
        lock.lock(); defer { lock.unlock() }
        map[hit.listingID] = Entry(hit: hit, expiry: nil, isLiked: true) // pinned
    }

    func demoteFromLiked(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        guard let e = map[id] else { return }
        map[id] = Entry(hit: e.hit,
                        expiry: Date().timeIntervalSince1970 + ListingCachePolicy.viewTTL,
                        isLiked: false)
    }

    // MARK: Sold / Remove
    func markSold(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        map[id] = nil
    }

    func removeAllExpired() {
        lock.lock(); defer { lock.unlock() }
        let now = Date().timeIntervalSince1970
        map = map.filter { _, e in e.expiry == nil || now < e.expiry! }
    }
}

// Images: pin liked, TTL for viewed
final class ListingImageCache {
    static let shared = ListingImageCache()
    private let volatile = NSCache<NSString, UIImage>() // viewed (TTL done via URLCache or manual)
    private var pinned: [String: UIImage] = [:]         // liked
    private let lock = NSLock()

    func image(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let img = pinned[url.absoluteString] { return img }
        return volatile.object(forKey: url.absoluteString as NSString)
    }

    func putViewed(_ img: UIImage, for url: URL?) {
        guard let url else { return }
        volatile.setObject(img, forKey: url.absoluteString as NSString)
    }

    func pinLiked(_ img: UIImage, for url: URL?) {
        guard let url else { return }
        lock.lock(); defer { lock.unlock() }
        pinned[url.absoluteString] = img
    }

    func unpinLiked(for url: URL?) {
        guard let url else { return }
        lock.lock(); defer { lock.unlock() }
        pinned[url.absoluteString] = nil
    }

    func purgeForListing(id: String, heroURL: URL?) {
        lock.lock(); defer { lock.unlock() }
        if let u = heroURL?.absoluteString { pinned[u] = nil; volatile.removeObject(forKey: u as NSString) }
    }
}