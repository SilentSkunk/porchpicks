//
//  MatchNotifications.swift
//  Exchange
//
//  Created by William Hunsucker on 9/18/25.
//


import Foundation
import UserNotifications
import FirebaseFirestore
import FirebaseMessaging
import UIKit

/// Local + (optional) FCM notifications for buyer pattern matches.
/// Listens to: users/{uid}/matchInbox (fields: listingId, searchId, brandLower, score, seen, createdAt, listingRef, sellerUid)
final class MatchNotifications: NSObject, ObservableObject {
    static let shared = MatchNotifications()

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var currentUid: String?
    private var hasRegisteredCategories = false

    // MARK: - Public API

/// Call once at app launch.
/// NOTE: Firebase must already be configured by AppDelegate (via FirebaseApp.configure()).
/// This helper does not call FirebaseApp.configure().
    func configureAndRequestAuth(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().delegate = self
        registerCategoriesIfNeeded()

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    DispatchQueue.main.async {
                        if granted {
                            UIApplication.shared.registerForRemoteNotifications()
                            // Proactively request FCM token on first authorization so it gets saved for new users
                            Messaging.messaging().token { token, error in
                                if let token = token, !token.isEmpty {
                                    AuthManager.shared.updateFCMTokenWith(token)
                                }
                            }
                        }
                        completion?(granted)
                    }
                }
            default:
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                    // Proactively request FCM token when notifications are already authorized
                    Messaging.messaging().token { token, error in
                        if let token = token, !token.isEmpty {
                            AuthManager.shared.updateFCMTokenWith(token)
                        }
                    }
                    completion?(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
                }
            }
        }
    }

    /// Start listening for new matches for a signed-in user.
    func startListening(for uid: String) {
        guard currentUid != uid else { return }
        stopListening()
        currentUid = uid

        let col = db.collection("users").document(uid).collection("matchInbox")
        // newest first; we’ll react only to .added changes
        listener = col
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                if let err {
                    #if DEBUG
                    print("[MatchNotifications] snapshot error: \(err)")
                    #endif
                    return
                }
                guard let snap else { return }

                for change in snap.documentChanges where change.type == .added {
                    let data = change.document.data()
                    let seen = data["seen"] as? Bool ?? false
                    guard seen == false else { continue }

                    let listingId  = data["listingId"] as? String ?? change.document.documentID
                    let brandLower = (data["brandLower"] as? String)?.capitalized ?? "Match"
                    let score      = data["score"] as? Double ?? 0.0
                    let searchId   = data["searchId"] as? String ?? ""

                    self.postLocalMatchNotification(
                        title: "New \(brandLower) match found",
                        body:  String(format: "Similarity score %.0f%% — tap to view", score * 100),
                        userInfo: [
                            "listingId": listingId,
                            "brandLower": brandLower.lowercased(),
                            "searchId": searchId,
                            "uid": uid
                        ],
                        identifier: "match_\(listingId)"
                    )
                }
            }

        #if DEBUG
        print("[MatchNotifications] listening started")
        #endif
    }

    /// Stop listening (e.g., on sign-out).
    func stopListening() {
        listener?.remove()
        listener = nil
        currentUid = nil
        #if DEBUG
        print("[MatchNotifications] stopped listening")
        #endif
    }

    /// Optionally mark a match as seen (call from your listing screen after opening).
    func markSeen(uid: String, listingId: String) {
        db.collection("users").document(uid).collection("matchInbox").document(listingId)
            .setData(["seen": true], merge: true)
    }

    // MARK: - FCM glue (optional)

    /// Forward APNs token from AppDelegate here to link APNs → FCM.
    func setAPNSToken(_ token: Data) {
        Messaging.messaging().apnsToken = token
    }

    // MARK: - Private

    private func registerCategoriesIfNeeded() {
        guard !hasRegisteredCategories else { return }
        hasRegisteredCategories = true

        let open = UNNotificationAction(
            identifier: "OPEN_LISTING",
            title: "Open",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: "MATCH_CATEGORY",
            actions: [open],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func postLocalMatchNotification(title: String, body: String, userInfo: [AnyHashable: Any], identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        content.userInfo = userInfo
        content.categoryIdentifier = "MATCH_CATEGORY"
        // Optional badge bump – adjust to your own badge strategy:
        // content.badge = NSNumber(value: (UIApplication.shared.applicationIconBadgeNumber + 1))

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.8, repeats: false)
        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(req) { err in
            #if DEBUG
            if let err { print("[MatchNotifications] schedule error: \(err)") }
            #endif
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension MatchNotifications: UNUserNotificationCenterDelegate {
    // Foreground presentation
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    // Tap handling
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {

        let info = response.notification.request.content.userInfo
        if let listingId = info["listingId"] as? String {
            // Post an app-wide notification / callback so your router can open the listing.
            NotificationCenter.default.post(name: .openListingDeepLink, object: nil, userInfo: ["listingId": listingId])

            // Optionally mark seen (needs uid in payload):
            if let uid = info["uid"] as? String {
                markSeen(uid: uid, listingId: listingId)
            }
        }
        completionHandler()
    }
}

// MARK: - App-wide helper notification name

extension Notification.Name {
    static let openListingDeepLink = Notification.Name("openListingDeepLink")
}
