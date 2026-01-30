//
//  AppConstants.swift
//  Exchange
//
//  App-wide constants to avoid magic numbers and strings scattered throughout the codebase.
//

import Foundation
import CoreGraphics

enum AppConstants {

    // MARK: - Deep Links
    enum DeepLinks {
        static let scheme = "vestivia"
        static let listingPath = "listing"

        static func listingURL(for listingId: String) -> URL? {
            URL(string: "\(scheme)://\(listingPath)/\(listingId)")
        }

        static let websiteBase = "https://vestivia.com"

        static func webListingURL(for listingId: String) -> URL {
            URL(string: "\(websiteBase)/listing/\(listingId)") ?? URL(string: websiteBase)!
        }
    }

    // MARK: - Image Compression
    enum ImageCompression {
        /// Standard quality for listing images
        static let standardQuality: CGFloat = 0.8
        /// Higher quality for thumbnails that need more detail
        static let thumbnailQuality: CGFloat = 0.70
        /// Quality for pattern matching images
        static let patternQuality: CGFloat = 0.85
    }

    // MARK: - Listing Validation
    enum Listing {
        /// Maximum characters allowed in a listing description
        static let maxDescriptionLength = 1000
        /// Maximum price in cents ($100,000.00)
        static let maxPriceCents = 100_000_00
        /// Maximum price as a Double for display
        static let maxPriceDouble: Double = 100_000.00
        /// Minimum required images for a listing
        static let minRequiredImages = 1
        /// Maximum images allowed per listing
        static let maxImages = 10
    }

    // MARK: - Networking
    enum Networking {
        /// Default timeout for network requests in seconds
        static let defaultTimeout: TimeInterval = 30
        /// Number of retry attempts for failed uploads
        static let uploadRetryAttempts = 3
        /// Base delay between retries in seconds (exponential backoff)
        static let retryBaseDelay: TimeInterval = 1.0
    }

    // MARK: - Cache
    enum Cache {
        /// Debounce delay for disk writes in nanoseconds (500ms)
        static let diskWriteDebounceNanos: UInt64 = 500_000_000
        /// Search debounce delay in nanoseconds (300ms)
        static let searchDebounceNanos: UInt64 = 300_000_000
    }

    // MARK: - UI
    enum UI {
        /// Standard avatar size
        static let avatarSize: CGFloat = 110
        /// Thumbnail size for list rows
        static let listThumbnailSize: CGFloat = 50
        /// Grid thumbnail size
        static let gridThumbnailSize: CGFloat = 44
        /// Standard corner radius
        static let cornerRadius: CGFloat = 8
        /// Large corner radius for cards
        static let cardCornerRadius: CGFloat = 16
    }

    // MARK: - Firebase Collections
    enum Firebase {
        static let usersCollection = "users"
        static let listingsCollection = "listings"
        static let ordersCollection = "orders"
        static let cartCollection = "cart"
        static let likesCollection = "likes"
        static let activeSearchesCollection = "active_searches"
    }

    // MARK: - Input Sanitization
    enum InputSanitization {
        /// Maximum allowed length for user-generated text fields
        static let maxTextFieldLength = 1000
        static let maxTitleLength = 200
        static let maxUsernameLength = 30

        /// Characters that should be stripped from user input to prevent injection
        private static let dangerousCharacters = CharacterSet(charactersIn: "<>\"'`\\")

        /// Sanitizes user input by trimming whitespace and removing potentially dangerous characters
        static func sanitize(_ input: String, maxLength: Int = maxTextFieldLength) -> String {
            var sanitized = input.trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove potentially dangerous characters
            sanitized = String(sanitized.unicodeScalars.filter { !dangerousCharacters.contains($0) })
            // Limit length
            if sanitized.count > maxLength {
                sanitized = String(sanitized.prefix(maxLength))
            }
            return sanitized
        }

        /// Sanitizes a title field (shorter max length, single line)
        static func sanitizeTitle(_ input: String) -> String {
            let singleLine = input.replacingOccurrences(of: "\n", with: " ")
            return sanitize(singleLine, maxLength: maxTitleLength)
        }

        /// Sanitizes username (alphanumeric + underscore only)
        static func sanitizeUsername(_ input: String) -> String {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
            let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
            return String(filtered.prefix(maxUsernameLength))
        }

        /// Validates that a price string is safe (numeric with optional decimal)
        static func isValidPriceFormat(_ input: String) -> Bool {
            let cleaned = input.replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespaces)
            return Double(cleaned) != nil
        }
    }
}
