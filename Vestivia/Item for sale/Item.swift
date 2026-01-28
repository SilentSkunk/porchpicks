//
//  Item.swift
//  Exchange
//
//  Created by William Hunsucker on 7/20/25.
//

import Foundation
import SwiftUI

struct ExchangeUser: Identifiable, Hashable {
    let id: UUID
    var username: String
    var email: String
}

struct Item: Identifiable, Hashable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var price: Double
    var condition: String
    var dateListed: Date
    var brand: String
    var seller: ExchangeUser
    var imageName: String

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        price: Double,
        condition: String,
        dateListed: Date = Date(),
        brand: String,
        seller: ExchangeUser,
        imageName: String
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.price = price
        self.condition = condition
        self.dateListed = dateListed
        self.brand = brand
        self.seller = seller
        self.imageName = imageName
    }

    static func == (lhs: Item, rhs: Item) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Item: Searchable {
    var searchType: SearchResultType { .item }

    var searchTitle: String { title }

    var searchSubtitle: String? { brand }

    var searchImage: UIImage? {
        UIImage(named: imageName)
    }

    var searchKeywords: [String] {
        [title.lowercased(), brand.lowercased(), condition.lowercased(), description.lowercased(), seller.username.lowercased()]
    }
}
