//
//  ProfileViewModel.swift
//  Exchange
//
//  Created by William Hunsucker on 9/8/25.
//


// ConnectedProfileView.swift
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

final class ProfileViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var email: String = ""
    @Published var avatarImage: Image? = nil
    private var listener: ListenerRegistration?

    deinit { listener?.remove() }

    func start() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = Firestore.firestore().collection("users").document(uid)

        listener?.remove()
        listener = ref.addSnapshotListener { [weak self] snap, _ in
            guard let self = self else { return }
            let data = snap?.data() ?? [:]

            // Prefer usernameLower, then username, else email prefix
            let unameLower = (data["usernameLower"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let uname      = (data["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let emailVal   = (data["email"] as? String) ?? Auth.auth().currentUser?.email ?? ""
            let displayName = (unameLower?.isEmpty == false ? unameLower : (uname?.isEmpty == false ? uname : nil))
                ?? (emailVal.split(separator: "@").first.map(String.init) ?? "Your Name")

            // photoURL saved when user uploaded avatar
            let urlString = (data["photoURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url = URL(string: urlString)

            DispatchQueue.main.async {
                self.email = emailVal
                self.name  = displayName
                if let url, !urlString.isEmpty {
                    self.loadImage(from: url)
                } else {
                    self.avatarImage = nil
                }
            }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    private func loadImage(from url: URL) {
        // Use async/await to avoid memory leaks from nested closure captures
        Task { [weak self] in
            guard let self = self else { return }

            var req = URLRequest(url: url)
            req.cachePolicy = .returnCacheDataElseLoad

            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                guard let ui = UIImage(data: data) else { return }

                await MainActor.run { [weak self] in
                    self?.avatarImage = Image(uiImage: ui)
                }
            } catch {
                #if DEBUG
                print("[ProfileViewModel] Failed to load avatar: \(error.localizedDescription)")
                #endif
            }
        }
    }
}
