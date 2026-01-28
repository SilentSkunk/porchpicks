//
//  BrandFields.swift
//  Exchange
//
//  Created by William Hunsucker on 7/28/25.
//

// Centralized manager for all selectable brand options

import Foundation

struct Brand: Identifiable, Hashable {
    let id = UUID()
    let name: String
}

class BrandFields: ObservableObject {
    static let shared = BrandFields()

    @Published var brands: [Brand] = [
        Brand(name: "Beaufort Bonnet"), Brand(name: "Banbury Cross"),
        Brand(name: "Bella Bliss"), Brand(name: "Boden"), Brand(name: "Burt's Bees"),
        Brand(name: "Carters"), Brand(name: "Cat & Jack"), Brand(name: "Crewcuts"),
        Brand(name: "Gap"), Brand(name: "Hanna Andersson"),
        Brand(name: "Janie and Jack"), Brand(name: "Little English"),
        Brand(name: "Matilda Jane"), Brand(name: "Monica and Andy"),
        Brand(name: "Old Navy"), Brand(name: "Patagonia"), Brand(name: "Ralph Lauren"),
        Brand(name: "Rylee + Cru"), Brand(name: "Smocked Auctions"),
        Brand(name: "Southern Proper"), Brand(name: "Target"),
        Brand(name: "Tea Collection"), Brand(name: "The Proper Peony"),
        Brand(name: "Zara Kids"), Brand(name: "Zutano")
    ]

    static var allBrands: [Brand] {
        BrandFields.shared.brands
    }

    @Published var selectedBrand: Brand?
}
