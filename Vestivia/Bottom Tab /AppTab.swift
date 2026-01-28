//
//  AppTab.swift
//  Exchange
//
//  Created by William Hunsucker on 8/18/25.
//


import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case feed
    case shop
    case sell
    case myStore
    case pattern // renamed from `patternMatch`
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .feed: return "Feed"
        case .shop: return "Shop"
        case .sell: return "Sell"
        case .myStore: return "My Porch"
        case .pattern: return "Pattern"
        }
    }
    
    /// Suggestion for tab bar icons (SF Symbols names)
    var systemImage: String {
        switch self {
        case .feed: return "house"
        case .shop: return "bag"
        case .sell: return "plus.circle"
        case .myStore: return "person.crop.square"
        case .pattern: return "rectangle.3.group.bubble.left"
        }
    }
}
