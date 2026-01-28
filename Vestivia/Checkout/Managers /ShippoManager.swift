//
//  ShippoManager.swift
//  Exchange
//
//  Created by William Hunsucker on 11/10/25.
//


//
//  ShippoManager.swift
//  Exchange
//
//  Created by William Hunsucker on 11/10/25.
//

import Foundation
import FirebaseFunctions

/// Matches Poshmark-style USPS Priority Mail Flat Rate shipping
/// Flat $7.97 up to 5 lbs, 1–3 day delivery
final class ShippoManager: ObservableObject {
    
    /// The shared singleton instance (optional, if you prefer using directly)
    static let shared = ShippoManager()
    
    private let functions = Functions.functions(region: "us-central1")
    
    // MARK: - Static Pricing
    
    /// Flat rate used across all shipments (USD)
    static let flatRate: Double = 7.97
    
    /// USPS Priority label description
    static let serviceDescription = "USPS Priority Mail (1–3 days, up to 5 lbs)"
    
    // MARK: - Shipping Quote Model
    
    struct Quote {
        let carrier: String
        let service: String
        let cost: Double
        let etaDays: ClosedRange<Int>
    }
    
    // MARK: - Public API
    
    /// Returns a static flat-rate USPS shipping quote.
    func getFlatRateQuote() -> Quote {
        return Quote(
            carrier: "USPS",
            service: Self.serviceDescription,
            cost: Self.flatRate,
            etaDays: 1...3
        )
    }
    
    /// Simulates label purchase or calls Shippo Cloud Function (if configured).
    func buyLabelIfNeeded(listingId: String,
                          shippingAddress: [String: Any],
                          completion: @escaping (Result<[String: Any], Error>) -> Void) {
        
        // If no backend integration, return a dummy result
        #if DEBUG
        print("[ShippoManager] Simulating label purchase for listing \(listingId)")
        #endif
        
        let simulatedLabel: [String: Any] = [
            "carrier": "USPS",
            "service": Self.serviceDescription,
            "amount": Self.flatRate,
            "currency": "USD",
            "trackingNumber": "SIM\(Int.random(in: 100000...999999))US",
            "labelUrl": "https://example.com/label-\(listingId).pdf"
        ]
        
        completion(.success(simulatedLabel))
    }
}