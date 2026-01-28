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
}
