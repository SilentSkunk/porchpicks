//
//  SingleListing.swift
//  Exchange
//
//  Created by William Hunsucker on 7/28/25.
//

import SwiftUI

struct SingleListing: Codable, Identifiable {
    var id: UUID = UUID()
    var category: String
    var subcategory: String
    var size: String
    var condition: String
    var gender: String
    var description: String
    var color: String
    var originalPrice: String
    var listingPrice: String
    var brand: String
    
    // Store raw Data for Codable
    var imageData: [Data] = []
    
    // Computed property to convert to UIImage array
    var images: [UIImage] {
        imageData.compactMap { UIImage(data: $0) }
    }
    
    // Custom initializer to allow passing UIImages
    // WARNING: This runs JPEG compression synchronously. For UI responsiveness,
    // use the async factory method `create(...)` instead.
    init(
        category: String,
        subcategory: String,
        size: String,
        condition: String,
        gender: String,
        description: String,
        color: String,
        originalPrice: String,
        listingPrice: String,
        brand: String,
        images: [UIImage] = []
    ) {
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
        self.imageData = images.compactMap { $0.jpegData(compressionQuality: 0.8) }
    }

    /// Async factory method that compresses images on a background thread.
    /// Use this from UI code to prevent main thread blocking.
    static func create(
        category: String,
        subcategory: String,
        size: String,
        condition: String,
        gender: String,
        description: String,
        color: String,
        originalPrice: String,
        listingPrice: String,
        brand: String,
        images: [UIImage]
    ) async -> SingleListing {
        // Compress images on background thread to prevent UI freeze
        let compressedData: [Data] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = images.compactMap { $0.jpegData(compressionQuality: 0.8) }
                continuation.resume(returning: data)
            }
        }

        var listing = SingleListing(
            category: category,
            subcategory: subcategory,
            size: size,
            condition: condition,
            gender: gender,
            description: description,
            color: color,
            originalPrice: originalPrice,
            listingPrice: listingPrice,
            brand: brand,
            images: [] // Empty - we'll set imageData directly
        )
        listing.imageData = compressedData
        return listing
    }
}
