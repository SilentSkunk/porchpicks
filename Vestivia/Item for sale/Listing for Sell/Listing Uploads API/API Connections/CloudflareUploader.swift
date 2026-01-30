import Foundation
import UIKit
import FirebaseFunctions

/// Cloudflare Images helper:
/// 1) Ask Firebase for a one-time direct-upload URL (getCFDirectUploadURL)
/// 2) Upload the image (multipart/form-data, field name "file") directly to Cloudflare Images
/// 3) (Optional) Ask Firebase for a short-lived signed delivery URL (getSignedImageUrl)
final class CloudflareUploader {
    static let shared = CloudflareUploader()

    /// Use the same region you deployed your callable functions to
    private lazy var functions = Functions.functions(region: "us-central1")

    // MARK: - Rate Limiting
    /// Maximum uploads allowed per window
    private let maxUploadsPerWindow = 20
    /// Time window for rate limiting (in seconds)
    private let rateLimitWindowSeconds: TimeInterval = 60
    /// Track upload timestamps for rate limiting
    private var uploadTimestamps: [Date] = []
    /// Serial queue for thread-safe access to timestamps
    private let rateLimitQueue = DispatchQueue(label: "com.vestivia.cloudflare.ratelimit")

    // MARK: - Public API

    /// Uploads image data to Cloudflare Images via a one-time direct upload URL.
    /// - Returns: The Cloudflare `imageId` (store this on your Listing in Firestore).
    /// - Throws: If rate limit exceeded or upload fails.
    @discardableResult
    func uploadImage(imageData: Data, filename: String = "upload.jpg", mimeType: String = "image/jpeg") async throws -> String {
        // Check rate limit before proceeding
        try checkRateLimit()

        // 1) Get a one-time direct upload URL from Firebase
        let (uploadURL, _) = try await getDirectUploadURL()

        // 2) POST multipart/form-data with field name "file"
        let imageId = try await uploadToCloudflareDirectURL(uploadURL: uploadURL, imageData: imageData, mime: mimeType)

        // Record successful upload for rate limiting
        recordUpload()

        // 3) Return the Cloudflare image id (caller should persist it in Firestore)
        return imageId
    }

    /// Check if upload is allowed under rate limit
    private func checkRateLimit() throws {
        rateLimitQueue.sync {
            let now = Date()
            let windowStart = now.addingTimeInterval(-rateLimitWindowSeconds)

            // Remove timestamps outside the current window
            uploadTimestamps = uploadTimestamps.filter { $0 > windowStart }
        }

        let currentCount = rateLimitQueue.sync { uploadTimestamps.count }
        if currentCount >= maxUploadsPerWindow {
            throw NSError(
                domain: "CloudflareUploader",
                code: 429,
                userInfo: [NSLocalizedDescriptionKey: "Upload rate limit exceeded. Please wait before uploading more images."]
            )
        }
    }

    /// Record an upload timestamp for rate limiting
    private func recordUpload() {
        rateLimitQueue.sync {
            uploadTimestamps.append(Date())
        }
    }

    /// Returns a short-lived signed delivery URL for a given Cloudflare `imageId`.
    func getSignedImageURL(imageId: String, variant: String = "thumb", ttlSec: Int = 300) async throws -> URL {
        let payload: [String: Any] = [
            "imageId": imageId,
            "variant": variant,
            "ttlSec": ttlSec
        ]
        let result = try await functions.httpsCallable("getSignedImageUrl").call(payload)
        guard
            let dict = result.data as? [String: Any],
            let urlStr = dict["url"] as? String,
            let url = URL(string: urlStr)
        else {
            throw NSError(domain: "CloudflareUploader", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid response from getSignedImageUrl"])
        }
        return url
    }

    // MARK: - Internals

    /// Ask Firebase for the one-time direct upload URL (and account hash if you need it).
    private func getDirectUploadURL() async throws -> (uploadURL: URL, accountHash: String?) {
        let result = try await functions.httpsCallable("getCFDirectUploadURL").call()
        guard
            let data = result.data as? [String: Any],
            let urlString = data["uploadURL"] as? String,
            let uploadURL = URL(string: urlString)
        else {
            throw NSError(domain: "CloudflareUploader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid upload URL from getCFDirectUploadURL"])
        }
        let accountHash = data["accountHash"] as? String
        return (uploadURL, accountHash)
    }

    /// Perform the actual multipart/form-data upload to Cloudflare's direct_upload URL (v2).
    /// Field name must be "file". Returns the Cloudflare `imageId` from the JSON response.
    private func uploadToCloudflareDirectURL(uploadURL: URL, imageData: Data, mime: String = "image/jpeg") async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: uploadURL)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, resp) = try await URLSession.shared.upload(for: req, from: body)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "cf", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "<no body>"
            throw NSError(domain: "cf", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Upload failed: \(http.statusCode) \(msg)"])
        }

        // Parse JSON to extract result.id
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = obj?["result"] as? [String: Any]
        let imageId = result?["id"] as? String ?? ""
        if imageId.isEmpty {
            let msg = String(data: data, encoding: .utf8) ?? "<no body>"
            throw NSError(domain: "cf", code: -2, userInfo: [NSLocalizedDescriptionKey: "Upload succeeded but no imageId returned. Body: \(msg)"])
        }
        return imageId
    }

    private static func parseImageId(from data: Data) throws -> String {
        // Lightweight parse to avoid creating Codable models:
        // Look for `"id":"<value>"` under `"result":{...}`
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        if
            let result = json?["result"] as? [String: Any],
            let id = result["id"] as? String,
            !id.isEmpty
        {
            return id
        }
        // Fallback to plain text (useful for debugging error shapes)
        let text = String(data: data, encoding: .utf8) ?? "N/A"
        throw NSError(domain: "CloudflareUploader", code: -4, userInfo: [NSLocalizedDescriptionKey: "Could not parse Cloudflare imageId. Response: \(text)"])
    }
}

// MARK: - Small Data helper

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) {
            append(d)
        }
    }
}
