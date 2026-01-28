//
//  ListingFields.swift
//  Exchange
//
//  Created by William Hunsucker on 7/21/25.
//


// ListingFields.swift
// Centralized manager for all selectable field options (category, subcategory, condition, size, etc.)

import Foundation
import SwiftUI

class ListingFields: ObservableObject {
    static let shared = ListingFields()

    @Published var categories: [String] = [
        "Dresses", "Tops", "Bottoms", "Outerwear", "Sleepwear", "Swimwear", "Accessories"
    ]

    @Published var subcategories: [String: [String]] = [
        "Dresses": ["Short Sleeve", "Long Sleeve", "Sleeveless"],
        "Tops": ["Blouse", "T-Shirt", "Tank Top"],
        "Bottoms": ["Shorts", "Pants", "Skirt"],
        "Outerwear": ["Jacket", "Sweater", "Raincoat"],
        "Sleepwear": ["One Piece", "Two Piece"],
        "Swimwear": ["One Piece", "Two Piece"],
        "Accessories": ["Hat", "Shoes", "Socks"]
    ]

    @Published var conditions: [String] = [
        "New with Tags", "New without Tags", "Excellent Used Condition", "Good Used Condition", "Play Condition"
    ]

    @Published var sizes: [String] = [
        "NB", "0-3M", "3-6M", "6-12M", "12-18M", "18-24M",
        "2T", "3T", "4T", "5", "6", "7", "8", "10", "12", "14"
    ]

    @Published var genders: [String] = [
        "Girls", "Boys", "Unisex"
    ]

    @Published var colorOptions: [(name: String, color: Color)] = [
        ("Red", .red), ("Pink", .pink), ("Orange", .orange), ("Yellow", .yellow),
        ("Green", .green), ("Blue", .blue), ("Purple", .purple), ("Gold", .yellow),
        ("Silver", .gray.opacity(0.5)), ("Black", .black), ("Gray", .gray),
        ("White", .white), ("Cream", Color(red: 1, green: 0.95, blue: 0.8)),
        ("Brown", .brown), ("Tan", Color(red: 0.82, green: 0.7, blue: 0.5))
    ]

    @Published var shoeSizeOptions: [(name: String, color: Color)] = [
        // Baby Shoes (0–2 months)
        ("Baby 0", .gray), ("Baby 1", .gray), ("Baby 2", .gray),

        // Infant (2–12 months)
        ("Infant 3", .gray), ("Infant 4", .gray), ("Infant 5", .gray),

        // Toddler (1–3 years)
        ("6T", .gray), ("7T", .gray), ("8T", .gray), ("9T", .gray), ("10T", .gray),

        // Kids (4–6 years)
        ("K11", .gray), ("K12", .gray), ("K13", .gray),

        // Youth (7–13 years)
        ("1Y", .gray), ("2Y", .gray), ("3Y", .gray), ("4Y", .gray), ("5Y", .gray), ("6Y", .gray)
    ]

    // Properties for direct field access via key paths
    @Published var selectedCategory: String = ""
    @Published var selectedSubcategory: String = ""
    @Published var selectedCondition: String = ""
    @Published var selectedSize: String = ""
    @Published var selectedGender: String = ""
    
    // Support up to two selected colors
    @Published var selectedColors: [String] = []  // e.g., ["Yellow", "Blue"]
    
    // Back-compat convenience for code that still reads/writes `selectedColor`.
    // This maps to the first entry of `selectedColors`.
    var selectedColor: String {
        get { selectedColors.first ?? "" }
        set {
            if newValue.isEmpty {
                // clear the primary selection
                if !selectedColors.isEmpty { selectedColors.removeFirst() }
            } else if selectedColors.isEmpty {
                selectedColors = [newValue]
            } else {
                selectedColors[0] = newValue
            }
        }
    }
}
