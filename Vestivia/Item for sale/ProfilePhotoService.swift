import Foundation
import UIKit
import FirebaseStorage

enum ProfilePhotoService {
    static func upload(image: UIImage, for uid: String) async throws -> String {
        let normalizedImage = normalized(image)
        let resizedImage = squareResized(normalizedImage, target: 256)
        let compressedData = jpegDataUnderLimit(resizedImage, maxBytes: 120 * 1024)
        
        let path = "profile_images/\(uid)/avatar.jpg"
        let ref = Storage.storage().reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(compressedData, metadata: metadata)
        try saveToCache(compressedData, for: uid)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }
    
    private static func normalized(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return normalizedImage
    }
    
    private static func squareResized(_ image: UIImage, target: CGFloat) -> UIImage {
        let originalSize = image.size
        let sideLength = min(originalSize.width, originalSize.height)
        let x = (originalSize.width - sideLength) / 2.0
        let y = (originalSize.height - sideLength) / 2.0
        let cropRect = CGRect(x: x * image.scale, y: y * image.scale, width: sideLength * image.scale, height: sideLength * image.scale)
        
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
            return image
        }
        
        let croppedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: target, height: target), false, image.scale)
        croppedImage.draw(in: CGRect(x: 0, y: 0, width: target, height: target))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? croppedImage
        UIGraphicsEndImageContext()
        
        return resizedImage
    }
    
    private static func jpegDataUnderLimit(_ image: UIImage, maxBytes: Int) -> Data {
        var compression: CGFloat = 1.0
        let minCompression: CGFloat = 0.1
        guard var data = image.jpegData(compressionQuality: compression) else {
            return Data()
        }
        
        while data.count > maxBytes && compression > minCompression {
            compression -= 0.1
            if let compressedData = image.jpegData(compressionQuality: compression) {
                data = compressedData
            } else {
                break
            }
        }
        
        return data
    }
    
    static func cacheURL(for uid: String) -> URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDirectory.appendingPathComponent("avatar_\(uid).jpg")
    }
    
    static func saveToCache(_ data: Data, for uid: String) throws {
        let url = cacheURL(for: uid)
        try data.write(to: url, options: .atomic)
    }
    
    static func loadFromCache(for uid: String) -> UIImage? {
        let url = cacheURL(for: uid)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
    }
    
    static func fetchToCache(for uid: String) async throws -> URL {
        let path = "profile_images/\(uid)/avatar.jpg"
        let ref = Storage.storage().reference(withPath: path)
        let localURL = cacheURL(for: uid)
        try await ref.writeAsync(to: localURL)
        return localURL
    }
}

extension StorageReference {
    func writeAsync(to fileURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            _ = self.write(toFile: fileURL) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
