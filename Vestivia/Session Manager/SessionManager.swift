//
//  SessionManager.swift
//  Vestivia
//
//  Created by William Hunsucker on 7/20/25.
//


import Foundation
import Combine
import FirebaseCore
import FirebaseFirestore

class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var currentUser: User? = nil
    @Published var isLoggedIn: Bool = false

    // MARK: - Mock Login
    func mockLogin(as user: User) {
        self.currentUser = user
        self.isLoggedIn = true
    }

    // MARK: - Logout
    func logout() {
        self.currentUser = nil
        self.isLoggedIn = false
    }

    // MARK: - Firebase Hook (Future Ready)
    func loginWithFirebase(uid: String, completion: @escaping (Bool) -> Void) {
        // Ensure Firebase is configured
        guard FirebaseApp.app() != nil else {
            print("⚠️ Firebase not configured yet. Aborting loginWithFirebase.")
            completion(false)
            return
        }

        let db = Firestore.firestore()
        db.collection("users").document(uid).getDocument { snapshot, error in
            if let error = error {
                print("❌ Error fetching user: \(error)")
                completion(false)
                return
            }
            if snapshot?.data() != nil {
                // TODO: Map data to your User model
                // self.currentUser = User(from: data)
                self.isLoggedIn = true
                completion(true)
            } else {
                completion(false)
            }
        }
    }
}
