//
//  ListingSubmission.swift
//  Exchange
//
//  Created by William Hunsucker on 7/29/25.
//

//
//  ListingSubmission.swift
//  Exchange
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - Listing Upload Notifications
extension Notification.Name {
    static let listingUploadStarted = Notification.Name("listingUploadStarted")
    static let listingUploadProgress = Notification.Name("listingUploadProgress")
    static let listingUploadFailed = Notification.Name("listingUploadFailed")
    static let listingUploadCompleted = Notification.Name("listingUploadCompleted")
}

/// Lifecycle status for a listing
enum ListingStatus: String {
    case active
    case pending   // reserved while buyer is paying
    case sold
    case canceled  // buyer canceled
    case removed   // seller removed
}

extension ListingStatus {
    /// Whether the item should be considered available for purchase
    var isAvailable: Bool { self == .active }
}

class ListingSubmission {
    static let shared = ListingSubmission()
    
    private init() {}

    /// Converts a brand into a safe, lowercase folder name (e.g., "Burt's Bees" -> "burts-bees").
    private static func slugifyBrand(_ brand: String) -> String {
        let lowered = brand.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "- "))
        let cleaned = String(lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        // collapse spaces to hyphens and trim repeating hyphens
        let hyphenated = cleaned.replacingOccurrences(of: " ", with: "-")
        let collapsed = hyphenated.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func prepareSquareJPEG(_ data: Data, maxSize: CGFloat = 512, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let originalSize = image.size
        let sideLength = min(originalSize.width, originalSize.height)
        let cropRect = CGRect(
            x: (originalSize.width - sideLength) / 2,
            y: (originalSize.height - sideLength) / 2,
            width: sideLength,
            height: sideLength
        )
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else { return nil }
        let croppedImage = UIImage(cgImage: cgImage)
        
        let scale = maxSize / sideLength
        let newSize = CGSize(width: sideLength * scale, height: sideLength * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        croppedImage.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage?.jpegData(compressionQuality: quality)
    }

    /// Uploads a normalized square JPEG pattern image to Firebase Storage and returns the storage fullPath.
    private func uploadPatternImage(for brand: String, listingID: String, patternData: Data) async throws -> String {
        guard let processedData = prepareSquareJPEG(patternData) else {
            throw NSError(domain: "ListingSubmission", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid pattern image"])
        }
        let storage = Storage.storage()
        let brandLower = Self.slugifyBrand(brand)
        let path = "active_listing_patterns/brands/\(brandLower)/\(listingID)/pattern.jpg"
        let ref = storage.reference().child(path)
        try await ref.putDataAsync(processedData, metadata: ["contentType": "image/jpeg"])
        return ref.fullPath
    }

    func submit(listing: SingleListing) async {
        await submit(listing: listing, patternJPEGData: nil)
    }

    func submit(listing: SingleListing, patternJPEGData: Data?) async {
        #if DEBUG
        print("[ListingSubmission] Submitting listing")
        #endif

        // Notify UI that upload started
        await MainActor.run {
            NotificationCenter.default.post(name: .listingUploadStarted, object: nil)
        }

        var uploadedImageIds: [String] = []
        let totalImages = listing.imageData.count
        let maxRetries = 3

        // 1️⃣ Upload each image to Cloudflare with retry logic
        for (index, imageData) in listing.imageData.enumerated() {
            var attempts = 0
            var lastError: Error?
            var uploadSuccess = false

            while attempts < maxRetries && !uploadSuccess {
                do {
                    let imageId = try await CloudflareUploader.shared.uploadImage(imageData: imageData)
                    uploadedImageIds.append(imageId)
                    uploadSuccess = true
                    #if DEBUG
                    print("[ListingSubmission] Uploaded image \(index + 1)/\(totalImages)")
                    #endif

                    // Update progress
                    await MainActor.run {
                        let progress = Double(index + 1) / Double(totalImages)
                        NotificationCenter.default.post(
                            name: .listingUploadProgress,
                            object: nil,
                            userInfo: ["progress": progress, "current": index + 1, "total": totalImages]
                        )
                    }
                } catch {
                    lastError = error
                    attempts += 1
                    #if DEBUG
                    print("[ListingSubmission] Upload attempt \(attempts)/\(maxRetries) failed for image \(index + 1)")
                    #endif

                    if attempts < maxRetries {
                        // Exponential backoff before retry
                        try? await Task.sleep(nanoseconds: UInt64(attempts * 1_000_000_000))
                    }
                }
            }

            // If all retries failed for this image, abort the submission
            if !uploadSuccess {
                let errorMessage = "Failed to upload image \(index + 1) after \(maxRetries) attempts. Please check your connection and try again."
                #if DEBUG
                print("[ListingSubmission] \(errorMessage)")
                #endif

                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .listingUploadFailed,
                        object: nil,
                        userInfo: [
                            "error": errorMessage,
                            "failedIndex": index,
                            "underlyingError": lastError?.localizedDescription ?? "Unknown error"
                        ]
                    )
                }
                return // ✅ Stop submission instead of continuing with missing images
            }
        }

        // Verify we have at least one image
        guard !uploadedImageIds.isEmpty else {
            let errorMessage = "At least one image is required to create a listing."
            #if DEBUG
            print("[ListingSubmission] \(errorMessage)")
            #endif

            await MainActor.run {
                NotificationCenter.default.post(
                    name: .listingUploadFailed,
                    object: nil,
                    userInfo: ["error": errorMessage]
                )
            }
            return
        }

        // 2️⃣ Create JSON representation
        let listingID = UUID().uuidString
        // Sanitize user inputs before saving to Firestore
        let sanitizedDescription = AppConstants.InputSanitization.sanitize(listing.description)
        let sanitizedBrand = AppConstants.InputSanitization.sanitizeTitle(listing.brand)
        let sanitizedCategory = AppConstants.InputSanitization.sanitizeTitle(listing.category)
        let sanitizedSubcategory = AppConstants.InputSanitization.sanitizeTitle(listing.subcategory)

        let jsonListing: [String: Any] = [
            "category": sanitizedCategory,
            "subcategory": sanitizedSubcategory,
            "size": listing.size,
            "condition": listing.condition,
            "gender": listing.gender,
            "description": sanitizedDescription,
            "color": listing.color,
            "originalPrice": listing.originalPrice,
            "listingPrice": listing.listingPrice,
            "brand": sanitizedBrand,
            "imageIds": uploadedImageIds,
            // status fields
            "listingID": listingID,
            "status": ListingStatus.active.rawValue,   // active | pending | sold | canceled | removed
            "isAvailable": true,
            "sold": false
        ]

        // 4️⃣ Prepare final listing data for Firestore
        var finalListingData = jsonListing
        finalListingData["objectID"] = listingID
        finalListingData["imageIds"] = uploadedImageIds
        finalListingData["primaryImageId"] = uploadedImageIds.first ?? ""
        finalListingData["createdAt"] = Date().timeIntervalSince1970
        finalListingData["lastmodified"] = Date().timeIntervalSince1970 * 1000
        finalListingData["status"] = ListingStatus.active.rawValue
        finalListingData["isAvailable"] = true
        finalListingData["soldAt"] = NSNull() // placeholder until sold

        // Upload pattern image to Firebase Storage if present (via helper)
        if let patternData = patternJPEGData {
            do {
                let path = try await uploadPatternImage(for: listing.brand, listingID: listingID, patternData: patternData)
                finalListingData["patternImagePath"] = path
                finalListingData["patternBrand"] = Self.slugifyBrand(listing.brand)
                #if DEBUG
                print("[ListingSubmission] Uploaded pattern image")
                #endif
            } catch {
                #if DEBUG
                print("[ListingSubmission] Error uploading pattern image")
                #endif
            }
        }

        // ✅ Attach userId and seller handle if logged in
        if let user = Auth.auth().currentUser {
            finalListingData["userId"] = user.uid
            do {
                let userSnap = try await Firestore.firestore()
                    .collection("users")
                    .document(user.uid)
                    .getDocument()
                let username = (userSnap.data()?["username"] as? String) ?? ""
                let usernameLower = (userSnap.data()?["usernameLower"] as? String) ?? ""
                finalListingData["username"] = username
                finalListingData["usernameLower"] = usernameLower
            } catch {
                #if DEBUG
                print("[ListingSubmission] Could not fetch user profile")
                #endif
            }
        }

        // 5️⃣ Save the listing and atomically bump listingsVersion on the user profile
        do {
            guard let userId = finalListingData["userId"] as? String else {
                let errorMessage = "Cannot save listing: You must be logged in"
                #if DEBUG
                print("[ListingSubmission] \(errorMessage)")
                #endif

                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .listingUploadFailed,
                        object: nil,
                        userInfo: ["error": errorMessage]
                    )
                }
                return
            }
            finalListingData["path"] = "users/\(userId)/listings/\(listingID)"

            let db = Firestore.firestore()
            let listingRef = db.collection("users")
                .document(userId)
                .collection("listings")
                .document(listingID)
            let userRef = db.collection("users").document(userId)
            let publicRef = db.collection("all_listings").document(listingID)

            let batch = db.batch()
            batch.setData(finalListingData, forDocument: listingRef, merge: true)
            batch.setData([
                "listingsVersion": FieldValue.increment(Int64(1)),
                "lastListingsChange": FieldValue.serverTimestamp()
            ], forDocument: userRef, merge: true)

            // Create/refresh a compact, query-friendly public listing doc used by Home feed
            // NOTE: createdAt is set by serverTimestamp here for consistent ordering.
            let publicDoc: [String: Any] = [
                "listingID": listingID,
                "userId": userId,
                "username": finalListingData["username"] as? String ?? "",
                "usernameLower": finalListingData["usernameLower"] as? String ?? "",
                "brand": listing.brand,
                "brandLower": listing.brand.lowercased(),
                "category": listing.category,
                "subcategory": listing.subcategory,
                "size": listing.size,
                "condition": listing.condition,
                "listingPrice": listing.listingPrice,
                "primaryImageId": uploadedImageIds.first ?? "",
                "imageIds": uploadedImageIds,
                "path": finalListingData["path"] as? String ?? "",
                // status mirror
                "status": ListingStatus.active.rawValue,
                "isAvailable": true,
                "sold": false,
                // use server time so clients can `order(by: "createdAt", descending: true)`
                "createdAt": FieldValue.serverTimestamp()
            ]
            batch.setData(publicDoc, forDocument: publicRef, merge: true)

            try await batch.commit()
            #if DEBUG
            print("[ListingSubmission] Saved listing to Firestore")
            #endif

            // Notify UI of successful completion
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .listingUploadCompleted,
                    object: nil,
                    userInfo: ["listingID": listingID]
                )
            }
        } catch {
            #if DEBUG
            print("[ListingSubmission] Error saving listing to Firestore")
            #endif

            // Notify UI of failure
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .listingUploadFailed,
                    object: nil,
                    userInfo: ["error": "Failed to save listing: \(error.localizedDescription)"]
                )
            }
        }
    }

    /// Atomically updates the status for a listing in both the owner path and the public mirror.
    /// - Parameters:
    ///   - userId: Owner UID
    ///   - listingID: Listing identifier
    ///   - newStatus: New status to set
    func updateStatus(userId: String, listingID: String, to newStatus: ListingStatus) async throws {
        let db = Firestore.firestore()
        let listingRef = db.collection("users").document(userId).collection("listings").document(listingID)
        let publicRef = db.collection("all_listings").document(listingID)

        var updates: [String: Any] = [
            "status": newStatus.rawValue,
            "isAvailable": newStatus.isAvailable,
            "lastmodified": Date().timeIntervalSince1970 * 1000
        ]
        if newStatus == .sold {
            updates["sold"] = true
            updates["soldAt"] = FieldValue.serverTimestamp()
        } else {
            updates["sold"] = false
            updates["soldAt"] = FieldValue.delete()
        }

        let batch = db.batch()
        batch.setData(updates, forDocument: listingRef, merge: true)
        batch.setData(updates, forDocument: publicRef, merge: true)
        try await batch.commit()
        #if DEBUG
        print("[ListingSubmission] Updated status for listing to \(newStatus.rawValue)")
        #endif
    }
}

fileprivate extension StorageReference {
    func putDataAsync(_ uploadData: Data, metadata: [String: String]? = nil) async throws {
        let meta = StorageMetadata()
        if let contentType = metadata?["contentType"] {
            meta.contentType = contentType
        }

        #if DEBUG
        let byteCount = uploadData.count
        print("[Storage] putData start bytes=\(byteCount)")
        #endif

        return try await withCheckedThrowingContinuation { continuation in
            self.putData(uploadData, metadata: meta) { metadata, error in
                if let error = error as NSError? {
                    #if DEBUG
                    print("[Storage] putData failed")
                    #endif
                    continuation.resume(throwing: error)
                } else {
                    #if DEBUG
                    print("[Storage] putData ok")
                    #endif
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
