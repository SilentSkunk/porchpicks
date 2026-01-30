//
//  ProfileView.swift
//  Exchange
//
//  Created by William Hunsucker on 9/8/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - ProfileView (pure UI)
struct ProfileView: View {
    // Inject from your auth/user store
    let name: String
    let email: String
    let avatarURL: URL?      // remote avatar URL; nil shows placeholder

    // Handlers (hook these up to your flows)
    var onEditProfile: () -> Void = {}
    var onAddPin: () -> Void = {}
    var onSettings: () -> Void = {}
    var onInvite: () -> Void = {}
    var onLogout: () -> Void = {}
    var onEditAvatar: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                AvatarHeaderView(
                    name: name,
                    email: email,
                    avatarURL: avatarURL,
                    onEditAvatar: onEditAvatar
                )

                // Card with action rows
                VStack(spacing: 0) {
                    ProfileActionRow(
                        title: "Edit Profile",
                        systemIcon: "pencil",
                        action: onEditProfile
                    )
                    Divider().padding(.leading, 56)
                    ProfileActionRow(
                        title: "Payment",
                        systemIcon: "creditcard",
                        action: onAddPin
                    )
                    Divider().padding(.leading, 56)
                    ProfileActionRow(
                        title: "Settings",
                        systemIcon: "gearshape",
                        action: onSettings
                    )
                    Divider().padding(.leading, 56)
                    ProfileActionRow(
                        title: "Invite a friend",
                        systemIcon: "person.2",
                        action: onInvite
                    )
                }
                .cardStyle()

                // Logout row (separate card, red text)
                Button(action: onLogout) {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(uiColor: .systemRed).opacity(0.12))
                                .frame(width: 36, height: 36)
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.red)
                        }
                        Text("Logout")
                            .font(.system(.body, design: .rounded).weight(.regular))
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .cardStyle()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Avatar Header
private struct AvatarHeaderView: View {
    let name: String
    let email: String
    let avatarURL: URL?
    var onEditAvatar: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let url = avatarURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .scaledToFill()
                            case .empty:
                                ProgressView()
                            @unknown default:
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .scaledToFill()
                            }
                        }
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: 108, height: 108)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.white, lineWidth: 3)
                )
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)

                Button(action: onEditAvatar) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.blue))
                        .overlay(
                            Circle().stroke(.white, lineWidth: 2)
                        )
                }
                .accessibilityLabel("Edit profile photo")
                .offset(x: 6, y: 6)
            }

            Text(name)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            // Email pill
            Text(email)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Color.blue.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.blue.opacity(0.18), lineWidth: 0.6)
                        )
                        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
                )
        }
        .padding(.top, 8)
    }
}

// MARK: - Row
private struct ProfileActionRow: View {
    let title: String
    let systemIcon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: systemIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)
                }

                Text(title)
                    .font(.system(.body, design: .rounded).weight(.regular))
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card Style
private extension View {
    func cardStyle() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Wrapper that binds to your VM
struct ConnectedProfileView: View {
    @StateObject private var vm = ProfileViewModel()
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = true
    @State private var avatarURL: URL? = nil

    // You can pass these in from a parent if needed
    var onEditProfile: () -> Void = {}
    var onAddPin: () -> Void = {}
    var onSettings: () -> Void = {}
    var onInvite: () -> Void = {}
    var onLogout: () -> Void = {}
    var onEditAvatar: () -> Void = {}

    var body: some View {
        ProfileView(
            name: vm.name,
            email: vm.email,
            avatarURL: avatarURL,
            onEditProfile: onEditProfile,
            onAddPin: onAddPin,
            onSettings: onSettings,
            onInvite: onInvite,
            onLogout: handleLogout,
            onEditAvatar: onEditAvatar
        )
        .onAppear {
            vm.start()
            loadAvatar()
        }
    }

    private func loadAvatar() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let cacheURL = ProfilePhotoService.cacheURL(for: uid)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            avatarURL = cacheURL
            return
        }
        Task {
            do {
                let path = try await resolveAvatarPath(for: uid)
                let storageRef = Storage.storage().reference(withPath: path)
                _ = try await storageRef.writeAsync(toFile: cacheURL)
                await MainActor.run {
                    avatarURL = cacheURL
                }
            } catch {
                #if DEBUG
                print("[ProfileAvatar] Error loading avatar")
                #endif
            }
        }
    }

    private func resolveAvatarPath(for uid: String) async throws -> String {
        let docRef = Firestore.firestore().collection("users").document(uid)
        let doc = try await docRef.getDocument()
        if let avatarPath = doc.data()?["avatarPath"] as? String, !avatarPath.isEmpty {
            return avatarPath
        }
        return "profile_images/\(uid)/avatar.jpg"
    }

    private func handleLogout() {
        // Capture uid to clear cached avatar after sign out
        let uid = Auth.auth().currentUser?.uid
        do {
            try Auth.auth().signOut()
        } catch {
            #if DEBUG
            print("[Profile] Sign out error")
            #endif
        }

        // Clear avatar cache for the previous user
        if let uid = uid {
            let cacheURL = ProfilePhotoService.cacheURL(for: uid)
            try? FileManager.default.removeItem(at: cacheURL)
        }

        // Reset local UI
        avatarURL = nil

        // Tell root to show LoginView (VestiviaApp gates on this flag)
        isLoggedIn = false
    }
}

// MARK: - Preview
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ProfileView(
                name: "Sana Afzal",
                email: "sanaafzal291@gmail.com",
                avatarURL: nil
            )
        }
        .environment(\.colorScheme, .light)
    }
}
