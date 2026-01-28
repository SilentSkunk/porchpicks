//
//  UserAddress.swift
//  Exchange
//
//  Created by William Hunsucker on 11/23/25.
//

//
//  AddressManager.swift
//  Exchange
//
//  Created by ChatGPT on 11/23/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Address Model used across app
struct UserAddress: Identifiable, Codable {
    var id: String = "main"
    
    var fullName: String
    var address: String
    var city: String
    var country: String
    var phone: String
    var isPrimary: Bool = true
    
    var asDictionary: [String: Any] {
        return [
            "fullName": fullName,
            "address": address,
            "city": city,
            "country": country,
            "phone": phone,
            "isPrimary": isPrimary,
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }
}

@MainActor
final class AddressManager: ObservableObject {
    
    static let shared = AddressManager()
    
    private let db = Firestore.firestore()
    
    // Path example: users/{uid}/primaryaddress/main
    private func addressRef(for uid: String) -> DocumentReference {
        db.collection("users")
          .document(uid)
          .collection("primaryaddress")
          .document("main")
    }
    
    
    // ------------------------------------------------------------
    // MARK: - Load Primary Address
    // ------------------------------------------------------------
    func loadPrimaryAddress() async throws -> UserAddress? {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AddressError.notLoggedIn
        }
        
        let snapshot = try await addressRef(for: uid).getDocument()
        
        guard let data = snapshot.data() else {
            return nil // No address saved yet
        }
        
        let address = UserAddress(
            id: "main",
            fullName: data["fullName"] as? String ?? "",
            address: data["address"] as? String ?? "",
            city: data["city"] as? String ?? "",
            country: data["country"] as? String ?? "",
            phone: data["phone"] as? String ?? "",
            isPrimary: true
        )
        
        return address
    }
    
    
    // ------------------------------------------------------------
    // MARK: - Save / Update Address
    // ------------------------------------------------------------
    func savePrimaryAddress(_ address: UserAddress) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AddressError.notLoggedIn
        }
        
        try await addressRef(for: uid).setData(address.asDictionary, merge: true)
    }
    
    
    // ------------------------------------------------------------
    // MARK: - Error Handling
    // ------------------------------------------------------------
    enum AddressError: Error {
        case notLoggedIn
        case invalidData
    }
}
