import SwiftUI
import Firebase
import Foundation

@main
struct VestiviaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @AppStorage("username") private var savedUsername: String = ""
    @AppStorage("userProfileImage") private var userProfileImageData: Data?

    init() {
        // Quiet Firebase/Firestore logs as early as possible (applies to all build configs)
        FirebaseConfiguration.shared.setLoggerLevel(.error)
    }

    var body: some Scene {
        WindowGroup {
            if isLoggedIn {
                MainTabView(isLoggedIn: $isLoggedIn)
                    .onOpenURL { url in
                        handleIncomingURL(url)
                    }
                    .task {
                        runPostLaunchTasks()
                    }
            } else {
                LoginView(isLoggedIn: $isLoggedIn)
                    .onOpenURL { url in
                        handleIncomingURL(url)
                    }
                    .task {
                        runPostLaunchTasks()
                    }
            }
        }
    }
}

extension VestiviaApp {
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "vestivia" else { return }
        if url.host == "listing" {
            let listingId = url.lastPathComponent
            NotificationCenter.default.post(name: Notification.Name("didSelectListingFromPush"), object: nil, userInfo: ["listingId": listingId])
        }
    }

    private func runPostLaunchTasks() {
        // Configure URLCache once Firebase is initialized
        ImageCacheConfigurator.configureSharedURLCache(memoryMB: 120, diskMB: 600)

        // Preload thumbnails from the last saved featured feed so Shop appears instantly.
        let defaultCache = DefaultFeedCache<Porch_Pick.ListingHit>()
        if let cached = defaultCache.load() {
            let urls = cached.compactMap { $0.imageURLs?.first }.compactMap(URL.init(string:))
            ImagePrefetcher.prefetch(urls)
        }
    }
}
