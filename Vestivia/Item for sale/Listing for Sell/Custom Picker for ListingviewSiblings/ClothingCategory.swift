//
//  ClothingCategory.swift
//  Exchange
//
//  Created by William Hunsucker on 7/20/25.
//


import Foundation

struct ClothingCategory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subcategories: [String]
    
    static let allCategories: [ClothingCategory] = [
        ClothingCategory(
            name: "Tops",
            subcategories: ["T-Shirts", "Blouses", "Sweaters", "Hoodies", "Polo Shirts"]
        ),
        ClothingCategory(
            name: "Bottoms",
            subcategories: ["Jeans", "Shorts", "Skirts", "Leggings", "Pants"]
        ),
        ClothingCategory(
            name: "Dresses & Rompers",
            subcategories: ["Casual Dresses", "Party Dresses", "Rompers"]
        ),
        ClothingCategory(
            name: "Outerwear",
            subcategories: ["Jackets", "Coats", "Raincoats", "Vests"]
        ),
        ClothingCategory(
            name: "Sleepwear",
            subcategories: ["Pajamas", "Nightgowns", "Sleep Sacks"]
        ),
        ClothingCategory(
            name: "Swimwear",
            subcategories: ["One-Piece", "Two-Piece", "Rash Guards"]
        ),
        ClothingCategory(
            name: "Accessories",
            subcategories: ["Hats", "Bows", "Socks", "Shoes", "Scarves", "Gloves"]
        ),
        ClothingCategory(
            name: "Special Occasion",
            subcategories: ["Christening", "Holiday Outfits", "Pageant", "Birthday Sets"]
        )
    ]
}