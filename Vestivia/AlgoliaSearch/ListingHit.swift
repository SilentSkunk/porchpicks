//
//  ListingHit.swift
//  Exchange
//
//  Created by William Hunsucker on 8/8/25.
//

import Foundation

/// Algolia hit for a listing. Designed to be **forgiving** about legacy field names
/// and provide a single, reliable way to access the image id(s).
struct ListingHit: Codable, Identifiable {

    // MARK: Identity
    let listingID: String
    var id: String { listingID }

    // MARK: Core fields
    let category: String?
    let subcategory: String?
    let size: String?
    let condition: String?
    let gender: String?
    let description: String?
    let color: String?
    let originalPrice: String?
    let listingPrice: String?
    let brand: String?
    let path: String?
    // Seller identity (provided on Algolia records)
    let username: String?
    let usernameLower: String?
    let userId: String?

    /// Deprecated – legacy URL storage (pre–Cloudflare Images)
    let imageURLs: [String]?

    /// New Cloudflare image IDs (can be empty)
    let imageIds: [String]?

    /// Preferred / designated primary Cloudflare image ID
    let primaryImageId: String?

    let objectID: String?
    let createdAt: Double?

    // MARK: - Helpers

    /// Numeric helpers (optional use in sorting/filters)
    var listingPriceNumber: Double? { ListingHit.parsePrice(listingPrice) }
    var originalPriceNumber: Double? { ListingHit.parsePrice(originalPrice) }

    /// Returns the best image id to use (primary first, then first in list)
    var preferredImageId: String? {
        primaryImageId ?? imageIds?.first
    }

    /// Back-compat alias, mapped to `preferredImageId`
    var safePrimaryImageId: String? { preferredImageId }

    /// Returns all image IDs, or an empty array if none.
    var allImageIds: [String] { imageIds ?? [] }

    private static func parsePrice(_ value: String?) -> Double? {
        guard let s = value else { return nil }
        // Strip common formatting like "$", commas, spaces and newlines
        let cleaned = s.replacingOccurrences(of: "[\\n\\r$, ]", with: "", options: .regularExpression)
        return Double(cleaned)
    }

    // MARK: - Coding

    enum CodingKeys: String, CodingKey {
        case listingID

        case category, subcategory, size, condition, gender, description, color
        case originalPrice, listingPrice, brand
        case path
        case username
        case usernameLower
        case userId

        // --- decode-only aliases (historical / alternate keys) ---
        case userID            // camel with capital D
        case userid            // all lower
        case user_id           // snake_case
        case uid               // sometimes stored as uid

        case userName          // camel "userName"
        case sellerUsername    // explicit seller username
        case seller_name       // snake case
        case seller            // minimal alias
        case username_lower    // snake case lower

        case imageURLs

        // canonical modern keys
        case imageIds
        case primaryImageId

        // legacy/alternate spellings (accepted on decode only)
        case primaryImageID      // sometimes capital D
        case imageId             // singular
        case imageIDs            // plural w/ capital D
        case primary_image_id    // snake_case (defensive)
        case image_ids           // snake_case (defensive)
        case primaryimageid      // all lowercase defensive variant

        case objectID, createdAt
    }

    init(listingID: String,
         category: String?, subcategory: String?, size: String?, condition: String?, gender: String?, description: String?, color: String?,
         originalPrice: String?, listingPrice: String?, brand: String?, path: String?,
         username: String? = nil, usernameLower: String? = nil, userId: String? = nil,
         imageURLs: [String]?, imageIds: [String]?, primaryImageId: String?,
         objectID: String?, createdAt: Double?) {

        self.listingID = listingID
        self.category = category
        self.subcategory = subcategory
        self.size = size
        self.condition = condition
        self.gender = gender
        self.description = description
        self.color = color
        self.originalPrice = originalPrice
        self.listingPrice = listingPrice
        self.brand = brand
        self.path = path
        self.username = username
        self.usernameLower = usernameLower
        self.userId = userId
        self.imageURLs = imageURLs
        self.imageIds = imageIds
        self.primaryImageId = primaryImageId
        self.objectID = objectID
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // listing id (hard fail if missing)
        self.listingID = try c.decode(String.self, forKey: .listingID)

        // simple optionals
        self.category = try c.decodeIfPresent(String.self, forKey: .category)
        self.subcategory = try c.decodeIfPresent(String.self, forKey: .subcategory)
        self.size = try c.decodeIfPresent(String.self, forKey: .size)
        self.condition = try c.decodeIfPresent(String.self, forKey: .condition)
        self.gender = try c.decodeIfPresent(String.self, forKey: .gender)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.color = try c.decodeIfPresent(String.self, forKey: .color)

        // prices may be numeric or string; store as string
        func decodePrice(_ key: CodingKeys) -> String? {
            if let d = try? c.decode(Double.self, forKey: key) { return String(d) }
            if let s = try? c.decode(String.self, forKey: key) { return s }
            return nil
        }
        self.originalPrice = decodePrice(.originalPrice)
        self.listingPrice  = decodePrice(.listingPrice)

        self.brand = try c.decodeIfPresent(String.self, forKey: .brand)
        self.path = try c.decodeIfPresent(String.self, forKey: .path)

        // Seller identity - be forgiving about historical key variants
        let canonicalUsername      = try c.decodeIfPresent(String.self, forKey: .username)
        let altUserNameCamel       = try c.decodeIfPresent(String.self, forKey: .userName)
        let altSellerUsername      = try c.decodeIfPresent(String.self, forKey: .sellerUsername)
        let altSellerSnake         = try c.decodeIfPresent(String.self, forKey: .seller_name)
        let altSellerShort         = try c.decodeIfPresent(String.self, forKey: .seller)

        let canonicalUsernameLower = try c.decodeIfPresent(String.self, forKey: .usernameLower)
        let altUsernameLowerSnake  = try c.decodeIfPresent(String.self, forKey: .username_lower)

        let canonicalUserId        = try c.decodeIfPresent(String.self, forKey: .userId)
        let altUserIdCapD          = try c.decodeIfPresent(String.self, forKey: .userID)
        let altUserIdLower         = try c.decodeIfPresent(String.self, forKey: .userid)
        let altUserIdSnake         = try c.decodeIfPresent(String.self, forKey: .user_id)
        let altUid                 = try c.decodeIfPresent(String.self, forKey: .uid)

        self.username = canonicalUsername
            ?? altUserNameCamel
            ?? altSellerUsername
            ?? altSellerSnake
            ?? altSellerShort

        self.usernameLower = canonicalUsernameLower
            ?? altUsernameLowerSnake
            ?? self.username?.lowercased()

        self.userId = canonicalUserId
            ?? altUserIdCapD
            ?? altUserIdLower
            ?? altUserIdSnake
            ?? altUid

        // legacy url array (kept for transitional scenarios)
        self.imageURLs = try c.decodeIfPresent([String].self, forKey: .imageURLs)

        // image ids – support multiple historical spellings
        let idsCanonical  = try c.decodeIfPresent([String].self, forKey: .imageIds)
        let idsLegacyCaps = try c.decodeIfPresent([String].self, forKey: .imageIDs)
        let idsSnake      = try c.decodeIfPresent([String].self, forKey: .image_ids)
        let idSingular    = try c.decodeIfPresent(String.self, forKey: .imageId)

        var resolvedIds: [String]? = idsCanonical ?? idsLegacyCaps ?? idsSnake
        if resolvedIds == nil, let single = idSingular {
            resolvedIds = [single]
        }
        self.imageIds = resolvedIds

        // primary image id – support alternate spellings and singular fallback
        func decodePrimary(_ key: CodingKeys) -> String? {
            // decodeIfPresent may throw on type mismatch; swallow and return nil
            (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil
        }

        let p1 = decodePrimary(.primaryImageId)
        let p2 = decodePrimary(.primaryImageID)
        let p3 = decodePrimary(.primary_image_id)
        let p4 = decodePrimary(.primaryimageid)

        self.primaryImageId = p1 ?? p2 ?? p3 ?? p4 ?? idSingular ?? resolvedIds?.first

        self.objectID = try c.decodeIfPresent(String.self, forKey: .objectID)
        self.createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(listingID, forKey: .listingID)

        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(subcategory, forKey: .subcategory)
        try c.encodeIfPresent(size, forKey: .size)
        try c.encodeIfPresent(condition, forKey: .condition)
        try c.encodeIfPresent(gender, forKey: .gender)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(color, forKey: .color)

        try c.encodeIfPresent(originalPrice, forKey: .originalPrice)
        try c.encodeIfPresent(listingPrice, forKey: .listingPrice)

        try c.encodeIfPresent(brand, forKey: .brand)
        try c.encodeIfPresent(path, forKey: .path)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(usernameLower, forKey: .usernameLower)
        try c.encodeIfPresent(userId, forKey: .userId)

        try c.encodeIfPresent(imageURLs, forKey: .imageURLs)
        try c.encodeIfPresent(imageIds, forKey: .imageIds)
        try c.encodeIfPresent(primaryImageId, forKey: .primaryImageId)

        try c.encodeIfPresent(objectID, forKey: .objectID)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

/// Lightweight seller data used by UI rows
public struct ListingSeller: Equatable {
    public let id: String?
    public let username: String?
    public let usernameLower: String?

    public init(id: String?, username: String?, usernameLower: String?) {
        self.id = id
        self.username = username
        self.usernameLower = usernameLower
    }

    /// Prefer explicit username, then usernameLower, otherwise empty string
    public var displayName: String {
        let u = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.isEmpty { return u }
        let l = (usernameLower ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return l
    }
}

extension ListingHit {
    /// Convenience wrapper so views don’t need to poke into raw fields
    public var seller: ListingSeller {
        ListingSeller(id: userId, username: username, usernameLower: usernameLower)
    }
}

// MARK: - Presentation conveniences used by ListingDetailView
extension ListingHit {
    /// A reasonable display title synthesized from available fields.
    /// Prefers "Brand + Category", falling back to Brand, then Category, then "Listing".
    var title: String {
        let b = (brand ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let c = (category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !b.isEmpty, !c.isEmpty { return "\(b) \(c)" }
        if !b.isEmpty { return b }
        if !c.isEmpty { return c }
        return "Listing"
    }

    /// A display-friendly price string; falls back to empty string if missing.
    /// `listingPrice` in your model is already a string; keep it as-is for UI.
    var priceString: String {
        (listingPrice ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Prefer seller username for display, falling back to brand, then "Seller"
    var sellerDisplayName: String {
        let u = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.isEmpty { return u }
        let b = (brand ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty ? "Seller" : b
    }
}
