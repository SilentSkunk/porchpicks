//
//  LikesCacheFile.swift
//  Exchange
//
//  Created by William Hunsucker on 10/5/25.
//



import Foundation

/// Stored metadata for a cached hero image associated with a liked listing
struct CachedImageInfo: Codable {
    /// Cloudflare image id
    let imageId: String
    /// Variant name (e.g., "Card", "Thumbnail")
    let variant: String
    /// Local filename written under the per-user likes-images directory
    let localFilename: String
    /// Optional signed URL we used to fetch the bytes (for debugging/refresh)
    let signedURL: String?
    /// Optional expiry of the signed URL (used to decide when to refresh)
    let expiresAt: Date?
}

struct LikesCacheFile: Codable {
    let version: Int
    let uid: String
    let updatedAt: Date
    let likedIDs: [String]
    let summaries: [String: ListingSummary] // keyed by listingId
    /// Optional map of listingId -> image info (hero image cached on disk)
    let images: [String: CachedImageInfo]? // keyed by listingId
}

enum LikesCache {
    static let version = 2

    private static func dir() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("likes", isDirectory: true)
    }

    /// Directory to store per-user liked hero images
    private static func imagesDir(for uid: String) -> URL {
        dir().appendingPathComponent("images_\(uid)", isDirectory: true)
    }

    /// URL for an image file within the user's images directory
    static func imageFileURL(uid: String, filename: String) -> URL {
        imagesDir(for: uid).appendingPathComponent(filename)
    }

    /// Ensure images directory exists
    @discardableResult
    private static func ensureImagesDir(uid: String) -> URL {
        let d = imagesDir(for: uid)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Write raw image bytes for a liked listing's hero image
    static func writeImage(uid: String, filename: String, data: Data) {
        ensureImagesDir(uid: uid)
        do {
            try data.write(to: imageFileURL(uid: uid, filename: filename), options: .atomic)
        } catch {
            #if DEBUG
            print("[LikesCache] writeImage error:", error)
            #endif
        }
    }

    /// Read raw image bytes if present
    static func readImageData(uid: String, filename: String) -> Data? {
        let url = imageFileURL(uid: uid, filename: filename)
        return try? Data(contentsOf: url)
    }

    private static func url(for uid: String) -> URL {
        dir().appendingPathComponent("\(uid).json")
    }

    static func load(uid: String) -> LikesCacheFile? {
        let url = url(for: uid)
        guard
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(LikesCacheFile.self, from: data),
            file.version == version
        else { return nil }
        return file
    }

    static func save(uid: String, likedIDs: [String], summaries: [String: ListingSummary]) {
        save(uid: uid, likedIDs: likedIDs, summaries: summaries, images: nil)
    }

    /// Full save that can include cached image metadata (optional)
    static func save(uid: String,
                     likedIDs: [String],
                     summaries: [String: ListingSummary],
                     images: [String: CachedImageInfo]?) {
        let file = LikesCacheFile(
            version: version,
            uid: uid,
            updatedAt: Date(),
            likedIDs: likedIDs,
            summaries: summaries,
            images: images
        )
        do {
            try FileManager.default.createDirectory(at: dir(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(file)
            try data.write(to: url(for: uid), options: .atomic)
        } catch {
            #if DEBUG
            print("[LikesCache] save error:", error)
            #endif
        }
    }

    static func clear(uid: String) {
        try? FileManager.default.removeItem(at: url(for: uid))
    }
}
