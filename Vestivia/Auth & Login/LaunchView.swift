//
//  LaunchView.swift
//  Exchange
//
//  Created by William Hunsucker on 8/2/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

private enum OnboardingStep { case none, username, avatar }

struct LaunchView: View {
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @State private var step: OnboardingStep = .none
    @State private var usernameListener: ListenerRegistration?
    @State private var authHandle: AuthStateDidChangeListenerHandle?
    @State private var didAttachAuthListener = false

    var body: some View {
        Group {
            if isLoggedIn {
                MainTabView(isLoggedIn: $isLoggedIn)
            } else {
                LoginView(isLoggedIn: $isLoggedIn)
            }
        }
        .onAppear {
            log("onAppear")
            // Attach Firebase Auth listener once
            if !didAttachAuthListener {
                didAttachAuthListener = true
                authHandle = Auth.auth().addStateDidChangeListener { _, user in
                    let new = (user != nil)
                    let was = isLoggedIn
                    if was != new {
                        log("auth state changed: \(was) -> \(new)")
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isLoggedIn = new
                    }
                    // Re-evaluate onboarding gate whenever auth changes
                    configureUsernameGate()
                }
            }
            // Initial sync in case listener fires late
            syncLoginFlagFromAuth()
            configureUsernameGate()
        }
        .onChange(of: isLoggedIn) { old, new in
            log("onChange isLoggedIn: \(old) -> \(new)")
            configureUsernameGate()
        }
        .onDisappear {
            log("onDisappear -> removing listener")
            usernameListener?.remove()
            usernameListener = nil
            if let h = authHandle {
                Auth.auth().removeStateDidChangeListener(h)
                authHandle = nil
                didAttachAuthListener = false
                log("removed AuthStateDidChangeListener")
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { isLoggedIn && step != .none },
                set: { presented in if !presented { step = .none } }
            )
        ) {
            switch step {
            case .none:
                EmptyView()
            case .username:
                UsernameSetupView()
                    .onDisappear { configureUsernameGate() }
            case .avatar:
                if currentUID() != nil {
                    ProfileImageSetupView()
                        .onDisappear { configureUsernameGate() }
                } else {
                    ProgressView().task { configureUsernameGate() }
                }
            }
        }
    }
}

// MARK: - Private helpers
private extension LaunchView {
    func currentUID() -> String? { Auth.auth().currentUser?.uid }

    func syncLoginFlagFromAuth() {
        let was = isLoggedIn
        let now = (Auth.auth().currentUser != nil)
        isLoggedIn = now
        log("syncLoginFlagFromAuth() -> was: \(was) now: \(now)")
    }

    func configureUsernameGate() {
        // Tear down any prior listener to avoid duplicate callbacks
        usernameListener?.remove()
        usernameListener = nil

        guard isLoggedIn, let uid = currentUID() else {
            log("configureUsernameGate() guard failed; not logged in or uid nil")
            step = .none
            return
        }

        let userRef = Firestore.firestore().collection("users").document(uid)
        log("Attaching snapshot listener to users/\(uid)")
        usernameListener = userRef.addSnapshotListener { snap, error in
            if let error = error {
                log("listener error: \(error.localizedDescription)")
                // If error, keep user gated at username to ensure completion flow
                step = .username
                return
            }
            // Default
            var next: OnboardingStep = .none

            // If no user doc, force username step
            if snap == nil || snap?.data() == nil {
                log("no user doc -> username step")
                step = .username
                return
            }
            let data = snap!.data()!

            let username = (data["usernameLower"] as? String)
                ?? (data["username"] as? String)
                ?? ""
            let hasUsername = !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if !hasUsername {
                next = .username
            } else {
                let anyImage = (data["photoURL"] as? String)
                    ?? (data["profileImageURL"] as? String)
                    ?? (data["profileImageId"] as? String)
                    ?? (data["profileImageName"] as? String)
                    ?? ""
                let hasPhoto = !anyImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                next = hasPhoto ? .none : .avatar
            }

            if step != next {
                log("onboarding step: \(step) -> \(next)")
            }
            step = next
        }
    }

    func log(_ msg: String) {
        print("[LaunchView] \(msg)")
    }
}
