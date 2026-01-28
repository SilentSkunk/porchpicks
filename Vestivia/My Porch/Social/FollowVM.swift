//
//  FollowVM.swift
//  Exchange
//
//  Created by William Hunsucker on 10/16/25.
//


// FollowVM.swift
import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class FollowVM: ObservableObject {
    @Published var isFollowing = false
    @Published var followers = 0
    @Published var following = 0
    @Published var listings = 0
    @Published var username = "User"
    @Published var photoURL: URL?

    private var countsListener: ListenerRegistration?
    private var profileListener: ListenerRegistration?

    let targetUid: String

    init(targetUid: String) {
        self.targetUid = targetUid
    }

    func start() {
        // live counts
        countsListener = FollowService.shared.listenCounts(userUid: targetUid) { [weak self] f, g in
            Task { @MainActor in
                self?.followers = f
                self?.following = g
            }
        }
        // profile
        profileListener = FollowService.shared.listenProfile(userUid: targetUid) { [weak self] name, url in
            Task { @MainActor in
                self?.username = name
                self?.photoURL = url
            }
        }
        Task {
            // initial following state
            self.isFollowing = (try? await FollowService.shared.isFollowing(targetUid: targetUid)) ?? false
            // one-shot listings count
            self.listings = await FollowService.shared.fetchActiveListingsCount(for: targetUid)
        }
    }

    func stop() {
        countsListener?.remove(); countsListener = nil
        profileListener?.remove(); profileListener = nil
    }

    func toggleFollow() {
        Task {
            let previous = isFollowing
            isFollowing.toggle() // optimistic
            do {
                if isFollowing {
                    _ = try await FollowService.shared.follow(targetUid: targetUid)
                } else {
                    _ = try await FollowService.shared.unfollow(targetUid: targetUid)
                }
            } catch {
                // revert on error
                isFollowing = previous
            }
        }
    }
}