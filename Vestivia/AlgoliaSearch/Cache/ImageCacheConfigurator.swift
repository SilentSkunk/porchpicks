//
//  ImageCacheConfigurator.swift
//  Exchange
//
//  Configures a larger shared URLCache and provides a small disk cache
//  for **signed** Cloudflare Images (private variants like "Card").
//
//  Why both?
//  - URLCache.shared helps AsyncImage/URLSession reuse PUBLIC URLs (e.g., Thumbnail).
//  - For PRIVATE signed URLs (which expire), we cache the **bytes** by (imageId, variant)
//    so re-opens don’t require re-signing while entries are valid.
//
//  Notes:
//  - All logs are DEBUG-only and minimal.
//  - Liked images can be "pinned" (no TTL) until unliked or sold.
//  - This file has zero Firebase/Algolia deps.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - URLCache sizing (public image URLs)

/// Configure a larger shared URL cache for AsyncImage / URLSession so that
/// Cloudflare Images (thumbnails, etc.) can be reused instead of re-downloaded.
/// Call this once at app launch (e.g., in AppDelegate or @main App init()).
enum ImageCacheConfigurator {
    /// Sets a beefier URLCache.shared.
    static func configureSharedURLCache(memoryMB: Int = 100, diskMB: Int = 500) {
        let memory = memoryMB * 1024 * 1024
        let disk   = diskMB * 1024 * 1024

        URLCache.shared = URLCache(
            memoryCapacity: memory,
            diskCapacity: disk,
            diskPath: "com.exchange.sharedurlcache"
        )

        #if DEBUG
        // Keep this very short to avoid log noise.
        print("[IMGCache] URLCache.shared configured mem=\(memoryMB)MB disk=\(diskMB)MB")
        #endif
    }
}

/// Prefetch helper to warm the URLCache with **public** image URLs (e.g., Cloudflare …/Thumbnail).
/// Fire-and-forget, prefers cached data when available.
enum ImagePrefetcher {
    static func prefetch(_ urls: [URL], maxConcurrent: Int = 4, timeout: TimeInterval = 15) {
        guard !urls.isEmpty else { return }

        // Dedicated session that uses the shared cache and conservative concurrency.
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.urlCache = URLCache.shared
        cfg.httpMaximumConnectionsPerHost = max(1, min(maxConcurrent, 8))
        let session = URLSession(configuration: cfg)

        for url in urls {
            let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: timeout)
            let task = session.dataTask(with: req) { _, _, _ in }
            task.priority = URLSessionTask.lowPriority
            task.resume()
        }
    }
}

// MARK: - Disk cache for SIGNED images (bytes, keyed by (imageId, variant))

/// Variants we commonly use. Keep rawValue aligned with your CFVariant names.
public enum ImageVariant: String {
    case card = "Card"
    case thumbnail = "Thumbnail"
}

/// Metadata we persist alongside the cached bytes.
private struct DiskMeta: Codable {
    let id: String
    let variant: String
    let createdAt: TimeInterval
    let expiresAt: TimeInterval?   // nil = pinned (e.g., liked)
}

/// Actor-backed disk+memory image cache for signed/private image bytes.
public actor DiskImageCache {
    public static let shared = DiskImageCache()

    private let mem = NSCache<NSString, NSData>()
    private lazy var dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private func key(_ id: String, _ v: ImageVariant) -> String { "\(id)#\(v.rawValue)" }
    private func dataPath(_ id: String, _ v: ImageVariant) -> URL { dir.appendingPathComponent(key(id, v)).appendingPathExtension("img") }
    private func metaPath(_ id: String, _ v: ImageVariant) -> URL { dir.appendingPathComponent(key(id, v)).appendingPathExtension("json") }

    // MARK: Read

    /// Returns cached bytes if present and not expired. If expired, the files are removed.
    public func get(id: String, variant: ImageVariant) -> Data? {
        let k = key(id, variant) as NSString

        if let d = mem.object(forKey: k) { return d as Data }

        let mp = metaPath(id, variant)
        let dp = dataPath(id, variant)

        guard
            let mdata = try? Data(contentsOf: mp),
            let meta  = try? JSONDecoder().decode(DiskMeta.self, from: mdata),
            FileManager.default.fileExists(atPath: dp.path)
        else {
            // No meta or data, ensure cleanup.
            try? FileManager.default.removeItem(at: mp)
            try? FileManager.default.removeItem(at: dp)
            return nil
        }

        // Check expiry (nil = pinned forever)
        if let exp = meta.expiresAt, Date().timeIntervalSince1970 > exp {
            try? FileManager.default.removeItem(at: mp)
            try? FileManager.default.removeItem(at: dp)
            #if DEBUG
            print("[IMGCache] expired removed \(id) \(variant.rawValue)")
            #endif
            return nil
        }

        guard let bytes = try? Data(contentsOf: dp) else {
            try? FileManager.default.removeItem(at: mp)
            try? FileManager.default.removeItem(at: dp)
            return nil
        }

        mem.setObject(bytes as NSData, forKey: k)
        return bytes
    }

    // MARK: Write

    /// Save bytes with an optional expiration. Pass `nil` to pin (e.g., liked).
    public func set(id: String, variant: ImageVariant, data: Data, expiresAt: Date?) {
        let k = key(id, variant) as NSString
        mem.setObject(data as NSData, forKey: k)

        let dp = dataPath(id, variant)
        let mp = metaPath(id, variant)

        try? data.write(to: dp, options: .atomic)

        let meta = DiskMeta(
            id: id,
            variant: variant.rawValue,
            createdAt: Date().timeIntervalSince1970,
            expiresAt: expiresAt?.timeIntervalSince1970
        )
        if let mdata = try? JSONEncoder().encode(meta) {
            try? mdata.write(to: mp, options: .atomic)
        }

        #if DEBUG
        print("[IMGCache] stored \(id) \(variant.rawValue) bytes=\(data.count) exp=\(expiresAt?.timeIntervalSince1970.description ?? "nil")")
        #endif
    }

    public func remove(id: String, variant: ImageVariant) {
        mem.removeObject(forKey: key(id, variant) as NSString)
        try? FileManager.default.removeItem(at: dataPath(id, variant))
        try? FileManager.default.removeItem(at: metaPath(id, variant))
    }

    /// Remove items whose expiresAt is in the past. Pinned items (nil) are kept.
    public func purgeExpired() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "json" {
            if let d = try? Data(contentsOf: url),
               let meta = try? JSONDecoder().decode(DiskMeta.self, from: d),
               let exp = meta.expiresAt,
               Date().timeIntervalSince1970 > exp {
                let id = meta.id
                let variant = ImageVariant(rawValue: meta.variant) ?? .card
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: dataPath(id, variant))
                #if DEBUG
                print("[IMGCache] purged \(id) \(variant.rawValue)")
                #endif
            }
        }
    }
}

// MARK: - Convenience downloader for signed URLs

public enum SignedImageFetcher {
    /// Downloads from a **signed** URL and stores in DiskImageCache with expiration/pin rules.
    /// - Parameters:
    ///   - id: Cloudflare imageId.
    ///   - variant: Image variant (e.g., .card).
    ///   - url: Signed URL to download.
    ///   - ttl: Suggested TTL for non-liked images (default 7 days).
    ///   - pin: If true (liked), the entry is stored with no expiration.
    public static func downloadAndCache(id: String,
                                        variant: ImageVariant,
                                        url: URL,
                                        ttl: TimeInterval = 7 * 24 * 3600,
                                        pin: Bool = false) async throws -> Data {
        if let cached = await DiskImageCache.shared.get(id: id, variant: variant) {
            return cached
        }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let expDate: Date? = pin ? nil : Date().addingTimeInterval(ttl)
        await DiskImageCache.shared.set(id: id, variant: variant, data: data, expiresAt: expDate)
        return data
    }
}
