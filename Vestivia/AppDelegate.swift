import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging
import GoogleSignIn

enum TargetTab: String { case shop, home, search, sell, inbox, profile }
struct RouteKeys {
    static let listingId = "listingId"
    static let objectID = "objectID"
    static let deeplink = "deeplink"
    static let preserveTab = "preserveTab"
    static let targetTab = "targetTab"
}

extension Notification.Name {
    static let didSelectListingFromPush = Notification.Name("didSelectListingFromPush")
}

extension Notification.Name {
    static let didRequestRoute = Notification.Name("didRequestRoute")
}

class AppDelegate: UIResponder, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    
    private var lastPostedListingRoute: (id: String, ts: TimeInterval)?
    private let routePostDebounce: TimeInterval = 0.6
    
    func application(_ application: UIApplication,
                     willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Configure Firebase exactly once, as early as possible, without peeking (peeking logs I-COR000003)
        struct Once { static var didConfigure = false }
        if !Once.didConfigure {
            FirebaseApp.configure()
            Once.didConfigure = true
            #if DEBUG
            // --- Firebase configuration debug ---
            let bundleID = Bundle.main.bundleIdentifier ?? "nil"
            print("🔥 [Firebase Debug] Bundle ID: \(bundleID)")
            if let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") {
                print("🔥 [Firebase Debug] Plist Path: \(plistPath)")
                print("🔥 [Firebase Debug] Plist URL: \(URL(fileURLWithPath: plistPath).path)")
                if let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] {
                    if let appId = dict["GOOGLE_APP_ID"] as? String {
                        print("🔎 [Firebase Debug] GOOGLE_APP_ID: \(appId)")
                    }
                    if let projectId = dict["PROJECT_ID"] as? String {
                        print("🔎 [Firebase Debug] PROJECT_ID: \(projectId)")
                    }
                }
            } else {
                print("❌ [Firebase Debug] GoogleService-Info.plist not found in app bundle")
            }
            #endif
        }
        return true
    }
    
    // MARK: - UIApplicationDelegate
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        if #available(iOS 13.0, *) {
            UIWindow.appearance().overrideUserInterfaceStyle = .light
        }
        // Set Messaging delegate to receive FCM token refresh callbacks
        Messaging.messaging().delegate = self

        // Proactively fetch the current FCM token on launch and persist it
        Messaging.messaging().token { token, error in
            if let token = token, !token.isEmpty {
                AuthManager.shared.updateFCMTokenWith(token)
            }
        }
        // Push setup
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
        // If the app was launched from a notification, route immediately
        if let remote = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            handleInboundNotification(userInfo: remote)
        }
        if let url = launchOptions?[.url] as? URL {
            handleInboundURL(url)
        }
        return true
    }
    
    // MARK: - Remote notification lifecycle (token)
    
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Forward to Firebase or your push provider if needed
        Messaging.messaging().apnsToken = deviceToken
        // Re-retrieve FCM token now that APNs token is set
        Messaging.messaging().token { token, error in
            if let token = token, !token.isEmpty {
                AuthManager.shared.updateFCMTokenWith(token)
            }
        }
        #if DEBUG
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[Push] APNS token: \(tokenString)")
        #endif
    }
    
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[Push] Failed to register: \(error)")
    }
    
    // Receive data/background notifications and route if a user tapped from a terminated/background state (fallback for some iOS versions)
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        #if DEBUG
        print("[Push] didReceiveRemoteNotification userInfo: \(userInfo)")
        #endif
        // Only route if this was user-initiated or contains an explicit deeplink/listingId.
        handleInboundNotification(userInfo: userInfo)
        completionHandler(.noData)
    }
    
    // MARK: - Foreground message presentation (optional)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }
    
    // MARK: - Handle taps on notifications
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        handleInboundNotification(userInfo: userInfo)
    }
    
    // MARK: - Universal link / custom URL scheme
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {

        // --- Google Sign‑In handler ---
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }

        // --- Existing deep link handling ---
        if let listingId = listingIdFrom(url: url) {
            postListingSelection(listingId)
            return true
        }

        return false
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
            handleInboundURL(url)
            return true
        }
        return false
    }
    
    // MARK: - Helpers
    
    private func handleInboundNotification(userInfo: [AnyHashable: Any]) {
        #if DEBUG
        print("[Push] User tapped notification with userInfo: \(userInfo)")
        #endif
        
        // Accept alternate key name as well
        if let objectID = userInfo[RouteKeys.objectID] as? String, !objectID.isEmpty {
            postListingSelection(objectID)
            return
        }
        
        // Prefer explicit listingId in payload
        if let listingId = userInfo[RouteKeys.listingId] as? String, !listingId.isEmpty {
            postListingSelection(listingId)
            return
        }
        
        // Otherwise parse from deeplink like "vestivia://listing/<id>"
        if let deeplink = userInfo[RouteKeys.deeplink] as? String,
           let url = URL(string: deeplink),
           let listingId = listingIdFrom(url: url) {
            postListingSelection(listingId)
            return
        }
        
        #if DEBUG
        print("[Push] No listingId or deeplink could be parsed from payload.")
        #endif
    }
    
    private func handleInboundURL(_ url: URL) {
        if let listingId = listingIdFrom(url: url) {
            postListingSelection(listingId)
        }
    }
    
    private func listingIdFrom(url: URL) -> String? {
        // Expect scheme: vestivia, host: listing, path: /<listingId>
        guard url.scheme?.lowercased() == "vestivia" else { return nil }
        guard url.host?.lowercased() == "listing" else { return nil }
        var id = url.lastPathComponent
        if id.isEmpty {
            // Fallback: try pathComponents
            let comps = url.pathComponents.filter { $0 != "/" }
            id = comps.last ?? ""
        }
        // Percent-decode just in case (e.g., "Test%206")
        id = id.removingPercentEncoding ?? id
        return id.isEmpty ? nil : id
    }
    
    private func postListingSelection(_ listingId: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let now = Date().timeIntervalSince1970
            if let last = self.lastPostedListingRoute, last.id == listingId, (now - last.ts) < self.routePostDebounce {
                #if DEBUG
                print("[Route] Suppressed duplicate route for listingId=\(listingId)")
                #endif
                return
            }
            self.lastPostedListingRoute = (listingId, now)

            #if DEBUG
            print("[Route] Post didSelectListingFromPush with listingId=\(listingId)")
            #endif

            let info: [String: Any] = [
                RouteKeys.listingId: listingId,
                RouteKeys.preserveTab: true,
                RouteKeys.targetTab: TargetTab.shop.rawValue
            ]

            // Legacy notification used by existing observers
            NotificationCenter.default.post(name: .didSelectListingFromPush, object: nil, userInfo: info)

            // New, more general route notification (optional for newer code paths)
            NotificationCenter.default.post(name: .didRequestRoute, object: nil, userInfo: info)
        }
    }
    
    // MARK: - UIScene support
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    // MARK: - Firebase Messaging delegate
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken, !token.isEmpty else { return }
        #if DEBUG
        print("[FCM] Registration token refreshed: \(token)")
        #endif
        AuthManager.shared.updateFCMTokenWith(token)
    }
}
