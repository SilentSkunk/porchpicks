//
//  UserProfile.swift
//  Exchange
//
//  Created by William Hunsucker on 8/21/25.
//

//
//  MessagesHomeUI.swift
//
//  Requires: FirebaseAuth, FirebaseFirestore, FirebaseFirestoreSwift
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Lightweight user directory (name + photo) with in-memory cache

struct UserProfile: Codable {
    var displayName: String?
    var photoURL: String?
}

actor UserDirectory {
    static let shared = UserDirectory()
    private var db: Firestore { Firestore.firestore() }
    private var cache: [String: UserProfile] = [:]

    func profile(for uid: String) async -> UserProfile? {
        if let c = cache[uid] { return c }
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            guard snap.exists else { return nil }
            let name = snap.get("displayName") as? String
            let url  = snap.get("photoURL") as? String
            let profile = UserProfile(displayName: name, photoURL: url)
            cache[uid] = profile
            return profile
        } catch { return nil }
    }
}

// MARK: - Helpers

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

private func relative(_ date: Date?) -> String {
    guard let d = date else { return "" }
    return relativeFormatter.localizedString(for: d, relativeTo: Date())
}

// MARK: - UI atoms

struct StoryAvatar: View {
    let imageURL: String?
    let name: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                    .frame(width: 58, height: 58)

                // Photo
                Group {
                    if let imageURL, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Image(systemName: "person.fill").resizable().scaledToFit().padding(12)
                        }
                        }
                    } else {
                        Image(systemName: "person.fill").resizable().scaledToFit().padding(12)
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(Circle())
            }

            Text(name)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 60)
        }
    }
}

struct ThreadRow: View {
    let title: String
    let subtitle: String
    let timeText: String
    let avatarURL: String?
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Group {
                if let avatarURL, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Image(systemName: "person.fill").resizable().scaledToFit().padding(10)
                        }
                    }
                } else {
                    Image(systemName: "person.fill").resizable().scaledToFit().padding(10)
                }
            }
            .frame(width: 48, height: 48)
            .background(Color.gray.opacity(0.15))
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text(timeText).font(.caption).foregroundColor(.secondary)
                }
                HStack(alignment: .top) {
                    Text(subtitle).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                    Spacer()
                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.caption2).bold()
                            .foregroundColor(.white)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 7)
                            .background(Capsule().fill(Color.blue))
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Main view

struct MessagesHomeView: View {
    @StateObject private var vm = ConversationsVM()

    @State private var searchText = ""
    // Fake “activities” list; swap with your own recent contacts if you like
    @State private var activities: [String] = [] // store UIDs here if you want real people

    var body: some View {
        VStack(spacing: 16) {

            // Search row
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search something…", text: $searchText)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))

                Button {
                    // present filters if you add them later
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title3)
                }
            }
            .padding(.horizontal)

            // Activities
            if !activities.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activities").font(.headline).padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(activities, id: \.self) { uid in
                                ActivityAvatar(uid: uid)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }

            // Messages list
            VStack(alignment: .leading, spacing: 8) {
                Text("Messages").font(.headline).padding(.horizontal)
                List {
                    ForEach(filtered(vm.conversations)) { conv in
                        NavigationLink {
                            if let cid = conv.id {
                                ChatView(vm: ChatVM(cid: cid))
                            } else {
                                Text("Missing conversation id")
                            }
                        } label: {
                            ThreadRowContainer(conv: conv)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { /* notifications */ } label: { Image(systemName: "bell") }
            }
        }
        .task {
            if let uid = Auth.auth().currentUser?.uid {
                vm.start(uid: uid)
            }
        }
        .onDisappear { vm.stop() }
    }

    private func filtered(_ items: [Conversation]) -> [Conversation] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { c in
            (c.title?.lowercased().contains(q) ?? false) ||
            (c.lastMessage?.lowercased().contains(q) ?? false)
        }
    }
}

// Wraps ThreadRow and resolves other member’s profile (name + photo)
struct ThreadRowContainer: View {
    let conv: Conversation
    @State private var displayName: String = "Conversation"
    @State private var avatarURL: String? = nil

    var body: some View {
        ThreadRow(
            title: displayName,
            subtitle: conv.lastMessage ?? "",
            timeText: relative(conv.updatedAt?.dateValue()),
            avatarURL: avatarURL,
            unreadCount: 0 // plug your unread logic later
        )
        .task {
            if let other = otherUID(in: conv) {
                if let profile = await UserDirectory.shared.profile(for: other) {
                    displayName = profile.displayName ?? "User"
                    avatarURL = profile.photoURL
                } else {
                    displayName = "User"
                    avatarURL = nil
                }
            } else {
                displayName = conv.title ?? "Conversation"
            }
        }
    }

    private func otherUID(in c: Conversation) -> String? {
        guard let me = Auth.auth().currentUser?.uid else { return nil }
        return c.members.first(where: { $0 != me })
    }
}

// “Stories/Activities” circle using the same user cache
struct ActivityAvatar: View {
    let uid: String
    @State private var profile: UserProfile?

    var body: some View {
        StoryAvatar(imageURL: profile?.photoURL, name: profile?.displayName ?? "User")
            .task {
                profile = await UserDirectory.shared.profile(for: uid)
            }
    }
}

// MARK: - Preview (pure UI with sample data)

struct MessagesHomeView_Previews: PreviewProvider {
    static var previews: some View {
        let sample = [
            Conversation(id: "c1", members: ["me", "u1"], lastMessage: "Hello hw are you? I am going to market. Do you want shopping?", lastSenderId: "u1", updatedAt: Timestamp(date: Date().addingTimeInterval(-23*60)), title: "Jhone Endrue"),
            Conversation(id: "c2", members: ["me", "u2"], lastMessage: "We are on the runways at the military hangar, there is a plane in it.", lastSenderId: "u2", updatedAt: Timestamp(date: Date().addingTimeInterval(-40*60)), title: "Jihane Luande"),
            Conversation(id: "c3", members: ["me", "u3"], lastMessage: "I received my new watch that I ordered from Amazon.", lastSenderId: "u3", updatedAt: Timestamp(date: Date().addingTimeInterval(-3600)), title: "Broman Alexander"),
            Conversation(id: "c4", members: ["me", "u4"], lastMessage: "I just arrived in front of the school. I'm waiting for you hurry up!", lastSenderId: "u4", updatedAt: Timestamp(date: Date().addingTimeInterval(-3600)), title: "Zack Jr")
        ]

        // A lightweight mock view that shows the layout without Firestore:
        NavigationStack {
            VStack(spacing: 16) {
                // Search row
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search something…", text: .constant(""))
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title3)
                }
                .padding(.horizontal)

                // Activities mock
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activities").font(.headline).padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(["Kristine","Kay","Cheryl","Jeen","Alex","Maya"], id: \.self) { name in
                                StoryAvatar(imageURL: nil, name: name)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Messages mock
                VStack(alignment: .leading, spacing: 8) {
                    Text("Messages").font(.headline).padding(.horizontal)
                    List {
                        ForEach(sample) { c in
                            ThreadRow(
                                title: c.title ?? "Conversation",
                                subtitle: c.lastMessage ?? "",
                                timeText: relative(c.updatedAt?.dateValue()),
                                avatarURL: nil,
                                unreadCount: Int.random(in: 0...2)
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Message")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
