//
//  Searchable.swift
//  Exchange
//
//  Created by William Hunsucker on 7/20/25.
//

//
//  User.swift
//  Vestivia
//
//  Created by William Hunsucker on 7/20/25.
//

import Foundation
import UIKit

enum SearchResultType: String, Codable {
    case brand
    case seller
    case item
}

protocol Searchable: Identifiable {
    var id: UUID { get }
    var searchType: SearchResultType { get }
    var searchTitle: String { get }
    var searchSubtitle: String? { get }
    var searchImage: UIImage? { get }
    var searchKeywords: [String] { get }
}

struct User: Identifiable, Searchable {
    let id: UUID
    let username: String
    let email: String
    let isSeller: Bool
    let profileImageName: String?
    let bio: String?
    let location: String?
    let rating: Double?
    let followerCount: Int?
    let followingCount: Int?

    var searchType: SearchResultType { .seller }
    var searchTitle: String { username }
    var searchSubtitle: String? { location }
    var searchImage: UIImage? {
        guard let name = profileImageName else { return nil }
        return UIImage(named: name)
    }

    var searchKeywords: [String] {
        return [username.lowercased(), email.lowercased()].compactMap { $0 }
    }
    
    var city: String? {
        return location
    }
}

extension User {
    static let sampleUsers: [User] = [
        User(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            username: "momofthree",
            email: "momofthree@example.com",
            isSeller: true,
            profileImageName: "profile_mom",
            bio: "Lover of vintage kids clothes and mom of 3!",
            location: "Austin, TX",
            rating: 4.8,
            followerCount: 320,
            followingCount: 180
        ),
        User(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            username: "jackson_dad",
            email: "dadj@example.com",
            isSeller: true,
            profileImageName: "profile_dad",
            bio: "Just a dad selling gently loved boy’s fashion.",
            location: "Nashville, TN",
            rating: 4.5,
            followerCount: 210,
            followingCount: 95
        ),
        User(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            username: "vintagequeen",
            email: "vintageq@example.com",
            isSeller: true,
            profileImageName: "profile_queen",
            bio: "Curated vintage outfits with a Southern flair.",
            location: "Charleston, SC",
            rating: 4.9,
            followerCount: 500,
            followingCount: 300
        )
    ]
}
