//
//  SellerProfileView.swift
//  Exchange
//
//  Created by William Hunsucker on 7/20/25.
//  Updated to fetch profile from Firestore by uid.
//

private extension Notification.Name {
    static let shopOpenListingRequested = Notification.Name("shopOpenListingRequested")
}

import SwiftUI
import FirebaseFirestore

// MARK: - Lightweight ViewModel-backed Profile View
struct SellerProfileView: View {
    /// Firestore document id of the seller in `users/{uid}`
    let uid: String
    @StateObject private var viewModel: SellerProfileViewModel
    @StateObject private var forSaleVM: ForSaleVM
    @StateObject private var likesVM: LikesVM
    @State private var avatarURLString: String? = nil
    @State private var avatarFileURL: URL? = nil
    enum SectionTab: String, CaseIterable, Identifiable {
        case forSale = "My Porch"
        case likes   = "My Picks"
        var id: String { rawValue }
    }
    @State private var selectedTab: SectionTab
    private let tabs: [SectionTab]

    init(uid: String, initialTab: SectionTab = .forSale) {
        self.uid = uid
        _viewModel = StateObject(wrappedValue: SellerProfileViewModel())
        _selectedTab = State(initialValue: initialTab)
        _forSaleVM = StateObject(wrappedValue: ForSaleVM(uid: uid))
        _likesVM = StateObject(wrappedValue: LikesVM(uid: uid))
        self.tabs = [.forSale, .likes]
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView().onAppear { viewModel.start(uid: uid) }

            case .error(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").imageScale(.large)
                    Text(message).font(.callout)
                    Button("Retry") { viewModel.start(uid: uid) }
                }
                .padding()

            case .loaded(let profile):
                content(profile: profile)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ProfilePhotoUpdated"))) { note in
            if let info = note.userInfo,
               let changedUid = info["uid"] as? String,
               changedUid == uid {
                // Prefer local cached file
                let url = ProfilePhotoService.cacheURL(for: uid)
                if FileManager.default.fileExists(atPath: url.path) {
                    avatarFileURL = url
                }
                // Keep string fallback if provided
                if let updated = info["url"] as? String {
                    avatarURLString = updated
                }
            }
        }
        .onAppear {
            let url = ProfilePhotoService.cacheURL(for: uid)
            if FileManager.default.fileExists(atPath: url.path) {
                avatarFileURL = url
            }
        }
        .onAppear {
            if selectedTab == .forSale {
                forSaleVM.start()
            } else {
                likesVM.start()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            switch newTab {
            case .forSale:
                forSaleVM.start(); likesVM.stop()
            case .likes:
                likesVM.start(); forSaleVM.stop()
            }
        }
        .onDisappear {
            forSaleVM.stop(); likesVM.stop()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Composed content
    func content(profile: SellerProfile) -> some View {
        VStack(spacing: 0) {
            profileHeader(profile: profile)
            Spacer(minLength: 40)
            tabsBar
            tabBody(profile: profile)
            Spacer(minLength: 8)
        }
    }
    
    @ViewBuilder
    private func profileHeader(profile: SellerProfile) -> some View {
        ZStack(alignment: .bottom) {
            // Banner
            Image("FrontPorch")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                .ignoresSafeArea(edges: .top)

            // Centered avatar + username + reviews
            VStack(spacing: 6) {
                ZStack {
                    // Image fills the full circle (110x110), then we draw the white ring on top.
                    Group {
                        if let fileURL = avatarFileURL {
                            AsyncImage(url: fileURL) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 110, height: 110)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 110)
                                        .clipShape(Circle())
                                case .failure:
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 110)
                                        .clipShape(Circle())
                                @unknown default:
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 110)
                                        .clipShape(Circle())
                                }
                            }
                        } else if let urlString = (avatarURLString ?? profile.profileImageURL),
                                  let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 110, height: 110)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 110)
                                        .clipShape(Circle())
                                case .failure:
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 110)
                                        .clipShape(Circle())
                                @unknown default:
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 110)
                                        .clipShape(Circle())
                                }
                            }
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 110, height: 110)
                                .clipShape(Circle())
                        }
                    }
                    // White border on top so the image appears to fill to the ring
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 110, height: 110)
                }
                Text(profile.username.isEmpty ? "User" : profile.username)
                    .font(.headline)
                Button(action: {}) {
                    Label("Reviews \(String(format: "%.1f", profile.rating))", systemImage: "star")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .cornerRadius(8)
                        .foregroundColor(.purple)
                }
            }
            .padding(.bottom, 0)
            .offset(y: 24) // slight overlap into white below the banner
        }
        .frame(height: 180) // enough space for avatar+text+reviews without overlapping next section
    }
    
    @ViewBuilder
    private func tabPill(_ tab: SectionTab) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(selectedTab == tab ? Color.purple : Color.clear)
            Text(tab.rawValue)
                .font(.callout.weight(.semibold))
                .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        }
    }
    
    @ViewBuilder
    private var tabsBar: some View {
        HStack(spacing: 6) {
            ForEach(tabs) { tab in
                tabPill(tab)
            }
        }
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func footer(profile: SellerProfile) -> some View {
        HStack {
            Spacer()
            Text("Showing items for \(profile.username)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
    
    @ViewBuilder
    private func tabBody(profile: SellerProfile) -> some View {
        switch selectedTab {
        case .forSale:
            listingList(items: forSaleVM.items, emptyText: "Nothing on your porch yet")
        case .likes:
            listingList(items: likesVM.items, emptyText: "No saved picks yet")
                .refreshable {
                    await likesVM.refreshNow()
                }
        }
    }

    // Prefer cached hero via LikesVM only; LikesVM already reads from LikesCacheFile internally
    private func cachedHeroURL(for id: String) -> URL? {
        return likesVM.cachedHeroURL(for: id)
    }

    @ViewBuilder
    private func thumbImage(url: URL?) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .resizable().scaledToFit().padding(8)
                @unknown default:
                    Image(systemName: "photo")
                        .resizable().scaledToFit().padding(8)
                }
            }
        } else {
            Image(systemName: "photo")
                .resizable().scaledToFit().padding(8)
        }
    }

    @ViewBuilder
    private func listingRow(_ item: ListingSummary) -> some View {
        let url = cachedHeroURL(for: item.id) ?? URL(string: item.thumbnailURL ?? "")
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                thumbImage(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(width: 50, height: 50)

            Text(item.title)
                .lineLimit(1)
            Spacer()
        }
    }

    @ViewBuilder
    private func listingList(items: [ListingSummary], emptyText: String) -> some View {
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .imageScale(.large)
                    .foregroundColor(.secondary)
                Text(emptyText).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        ListingDetailContainer(listingId: item.id)
                    } label: {
                        listingRow(item)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // Placeholder helpers for brand and price
    private func brandString(from item: ListingSummary) -> String { "" }
    private func priceString(from item: ListingSummary) -> String { "" }
}

@MainActor final class SellerProfileViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded(SellerProfile)
        case error(String)
    }

    @Published var state: State = .idle
    private var listener: ListenerRegistration?

    private lazy var db = Firestore.firestore()

    func start(uid: String) {
        stop()
        state = .loading

        let doc = db.collection("users").document(uid)
        listener = doc.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                self.state = .error(error.localizedDescription)
                return
            }
            guard let data = snapshot?.data() else {
                self.state = .error("Profile not found")
                return
            }
            self.state = .loaded(SellerProfile.from(dict: data, uid: uid))
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
        if case .loading = state { state = .idle }
    }
}

struct SellerProfile: Identifiable {
    let id: String
    let username: String
    let bio: String?
    let rating: Double
    let followerCount: Int
    let followingCount: Int
    let profileImageURL: String?

    static func from(dict: [String: Any], uid: String) -> SellerProfile {
        SellerProfile(
            id: uid,
            username: dict["username"] as? String ?? (dict["usernameLower"] as? String ?? "User"),
            bio: dict["bio"] as? String,
            rating: (dict["rating"] as? NSNumber)?.doubleValue ?? 0,
            followerCount: (dict["followerCount"] as? NSNumber)?.intValue ?? 0,
            followingCount: (dict["followingCount"] as? NSNumber)?.intValue ?? 0,
            profileImageURL: (
                (dict["profileImageURL"] as? String) ??
                (dict["profilePhotoURL"] as? String) ??
                (dict["photoURL"] as? String) ??
                (dict["avatarURL"] as? String)
            )
        )
    }
}

// MARK: - Preview
#if DEBUG
struct SellerProfileView_Previews: PreviewProvider {
    static let mockProfile = SellerProfile(
        id: "preview",
        username: "Preview User",
        bio: "Test bio",
        rating: 4.5,
        followerCount: 12,
        followingCount: 8,
        profileImageURL: nil
    )
    static var previews: some View {
        NavigationStack {
            SellerProfileView(uid: "preview-user-uid").content(profile: mockProfile)
        }
        .previewDisplayName("Seller Profile")
    }
}
#endif
