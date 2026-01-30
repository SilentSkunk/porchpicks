//
//  CFVariant.swift
//  Exchange
//
//  Created by William Hunsucker on 10/7/25.
//


//
//  CloudflareImages.swift
//  Exchange
//
//  Shared helpers for Cloudflare Images (public variants + signed variants)
//  No dependency on Algolia or InstantSearch.
//

import Foundation
import UIKit
import ImageIO

#if canImport(FirebaseFunctions)
@preconcurrency import FirebaseFunctions
#endif

// MARK: - Public variants (always accessible via CDN)

// NOTE: Set your Images Account Hash if it's not the same.
public enum CFVariant: String {
    case thumbnail = "Thumbnail"
    case card      = "Card"
}

/// Lightweight helper to build public (unsigned) Cloudflare Images URLs.
public enum CFImages {
    // Replace if you ever change the account hash
    public static var accountHash: String = "bh7zSZiTTc0igci1WPjT5w"

    /// https://imagedelivery.net/{ACCOUNT_HASH}/{imageId}/{variant}
    public static func publicURL(id: String, variant: CFVariant) -> URL? {
        guard !id.isEmpty else { return nil }
        // If the field is already a full URL, just return it.
        if id.hasPrefix("http://") || id.hasPrefix("https://") { return URL(string: id) }
        return URL(string: "https://imagedelivery.net/\(accountHash)/\(id)/\(variant.rawValue)")
    }

    /// Public thumbnail variant convenience.
    public static func publicThumbURL(id: String) -> URL? {
        publicURL(id: id, variant: .thumbnail)
    }
}

// MARK: - Signed URL cache (in-memory)

final class CFURLCache {
    static let shared = CFURLCache()
    private var store: [String: (url: URL, exp: TimeInterval)] = [:]   // key = "<id>#<variant>"
    private let queue = DispatchQueue(label: "cf.signed-url-cache")

    func get(id: String, variant: String) -> URL? {
        queue.sync {
            let key = "\(id)#\(variant)"
            guard let entry = store[key] else { return nil }
            let now = Date().timeIntervalSince1970
            // 10s safety margin to avoid returning URLs that are about to expire
            return now < (entry.exp - 10) ? entry.url : nil
        }
    }

    func set(id: String, variant: String, url: URL, exp: TimeInterval) {
        queue.async { [url] in
            self.store["\(id)#\(variant)"] = (url, exp)
        }
    }
}

// MARK: - Signed URL signer (Firestore-based)

import FirebaseFirestore

actor CloudflareSigner {
    static let shared = CloudflareSigner()
    private var cache: [String: (url: URL, exp: TimeInterval)] = [:]

    /// Fetch a signed URL for the given image ID using Firestore.
    /// Caches URLs in-memory for 10 minutes to reduce reads.
    func getSignedURL(for imageId: String?) async -> URL? {
        guard let imageId, !imageId.isEmpty else { return nil }

        let now = Date().timeIntervalSince1970
        if let cached = cache[imageId], now < (cached.exp - 10) {
            return cached.url
        }

        do {
            let doc = try await Firestore.firestore()
                .collection("signedCertificates")
                .document(imageId)
                .getDocument()

            if let urlString = doc.data()?["url"] as? String,
               let url = URL(string: urlString) {
                cache[imageId] = (url, now + 600)
                return url
            }
        } catch {
            print("[Signer] Error fetching signed URL: \(error)")
        }

        return nil
    }
}

// MARK: - Global convenience (nice to call directly from views)

// MARK: - Utilities your views can use


/// Choose the “best” image id from a listing-like object.
/// Order: preferredImageId → primaryImageId → imageIds.first.
/// Works for:
///  - your Listing model (via Mirror)
///  - a plain dictionary decoded from Firestore/Algolia
public func bestImageId(from listing: Any) -> String? {
    // 1) dictionary case
    if let dict = listing as? [String: Any] {
        let prefer = (dict["preferredImageId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = prefer, !s.isEmpty { return s }
        let primary = (dict["primaryImageId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = primary, !s.isEmpty { return s }
        if let ids = dict["imageIds"] as? [String] {
            return ids.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
        return nil
    }

    // 2) any Codable/struct with matching property names (using Mirror)
    let m = Mirror(reflecting: listing)
    if let s = m.children.first(where: { $0.label == "preferredImageId" })?.value as? String,
       !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
    if let s = m.children.first(where: { $0.label == "primaryImageId" })?.value as? String,
       !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
    if let ids = m.children.first(where: { $0.label == "imageIds" })?.value as? [String] {
        return ids.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }
    return nil
}

/// Build the **public** thumbnail URL (fast, no signing).
public func publicThumbURL(forImageId id: String?) -> URL? {
    guard let id, !id.isEmpty else { return nil }
    return CFImages.publicThumbURL(id: id)
}

/// Simple probe you can call in DEBUG to verify a URL returns image bytes.
/// Uses a HEAD request first (checks Content-Type), then falls back to a small
/// ranged GET and validates with ImageIO **without caching/decoding** to avoid
/// CoreGraphics warnings.
public func urlLooksLikeImage(_ url: URL?) async -> Bool {
    guard let url else { return false }

    // 1) Try HEAD for a quick content-type check
    do {
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        head.timeoutInterval = 6
        let (_, resp) = try await URLSession.shared.data(for: head)
        if let http = resp as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
            if let ct = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(), ct.hasPrefix("image/") {
                return true
            }
        }
    } catch { /* ignore and try ranged GET */ }

    // 2) Fallback: fetch a small slice and let ImageIO sniff it
    do {
        var req = URLRequest(url: url)
        req.setValue("bytes=0-1023", forHTTPHeaderField: "Range") // first ~1KB
        req.cachePolicy = .returnCacheDataElseLoad
        req.timeoutInterval = 6
        let (data, _) = try await URLSession.shared.data(for: req)
        guard data.count > 8 else { return false }

        // Create an image source without decoding or caching
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        if let src = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) {
            // If ImageIO can determine a type, treat it as an image
            if CGImageSourceGetType(src) != nil { return true }
        }
    } catch { /* fallthrough */ }

    return false
}
