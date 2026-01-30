import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import GoogleSignIn
import AuthenticationServices
import CryptoKit

/// Central auth/orchestration object used by LaunchView and onboarding.
/// Adds a simple state machine via `route` so UI can decide what to show
/// (loggedOut → needUsername → needPhoto → ready).
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    // MARK: Routing state
    enum Route { case loggedOut, needUsername, needPhoto, ready }
    @Published var route: Route = .loggedOut
    private var didStart = false

    private var authListener: AuthStateDidChangeListenerHandle?
    private var userListener: ListenerRegistration?
    private lazy var db = Firestore.firestore()

    private init() {
        // Intentionally empty: call start() after FirebaseApp.configure() in AppDelegate
    }

    deinit {
        if let authListener { Auth.auth().removeStateDidChangeListener(authListener) }
        userListener?.remove(); userListener = nil
    }

    /// Must be called once from AppDelegate's willFinishLaunching (after FirebaseApp.configure() has run).
    /// Do not call FirebaseApp.configure() here.
    func start() {
        guard !didStart else { return }
        didStart = true

        // Monitor Firebase Auth state and attach/detach a Firestore listener
        // on the current user's profile document to drive `route` updates.
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            self.userListener?.remove(); self.userListener = nil

            guard let uid = user?.uid else {
                self.route = .loggedOut
                return
            }
            self.attachUserDocListener(uid: uid)
            self.captureAndSaveCurrentFCMToken()
        }
    }

    // MARK: - Public helpers
    func isUserLoggedIn() -> Bool { Auth.auth().currentUser != nil }

    func signIn(email: String, password: String, completion: @escaping (Result<FirebaseAuth.User, Error>) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            if let error = error { completion(.failure(error)); return }
            guard let user = result?.user else { return }
            self.ensureUserContainers(uid: user.uid, email: user.email)
            self.attachUserDocListener(uid: user.uid)
            self.captureAndSaveCurrentFCMToken()
            completion(.success(user))
        }
    }

    func signUp(email: String, password: String, completion: @escaping (Result<FirebaseAuth.User, Error>) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error { completion(.failure(error)); return }
            guard let user = result?.user else { return }
            self.ensureUserContainers(uid: user.uid, email: user.email)
            self.attachUserDocListener(uid: user.uid)
            self.captureAndSaveCurrentFCMToken()
            completion(.success(user))
        }
    }

    /// Google Sign-In (restores previous session if possible, otherwise interactive)
    func signInWithGoogle(presenting viewController: UIViewController, completion: @escaping (Result<FirebaseAuth.User, Error>) -> Void) {
        GIDSignIn.sharedInstance.restorePreviousSignIn { restoredUser, restoreError in
            if let restoredUser = restoredUser {
                // Use restored session
                self.firebaseSignIn(with: restoredUser, completion: completion)
            } else {
                // Interactive sign-in
                GIDSignIn.sharedInstance.signIn(withPresenting: viewController) { signInResult, error in
                    if let error = error { completion(.failure(error)); return }
                    guard let user = signInResult?.user else {
                        completion(.failure(NSError(domain: "GoogleSignIn", code: -2, userInfo: [NSLocalizedDescriptionKey: "No Google sign-in result"])));
                        return
                    }
                    self.firebaseSignIn(with: user, completion: completion)
                }
            }
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
        userListener?.remove(); userListener = nil
        route = .loggedOut
    }

    // MARK: - Private
    private func firebaseSignIn(with googleUser: GIDGoogleUser, completion: @escaping (Result<FirebaseAuth.User, Error>) -> Void) {
        guard let idToken = googleUser.idToken?.tokenString else {
            completion(.failure(NSError(domain: "GoogleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Google ID token"])));
            return
        }
        let accessToken = googleUser.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        Auth.auth().signIn(with: credential) { result, error in
            if let error = error { completion(.failure(error)); return }
            guard let user = result?.user else { return }
            self.ensureUserContainers(uid: user.uid, email: user.email)
            self.attachUserDocListener(uid: user.uid)
            self.captureAndSaveCurrentFCMToken()
            completion(.success(user))
        }
    }

    private func attachUserDocListener(uid: String) {
        userListener?.remove()

        userListener = db.collection("users").document(uid).addSnapshotListener { [weak self] snap, _ in
            guard let self = self else { return }

            // If the user doc doesn't exist yet, treat as not onboarded.
            guard let data = snap?.data(), snap?.exists == true else {
                if self.route != .needUsername {
                    self.route = .needUsername
                }
                return
            }

            let username = (
                (data["usernameLower"] as? String) ??
                (data["username"] as? String) ??
                ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            let photo = (
                (data["photoURL"] as? String) ??
                (data["profileImageURL"] as? String) ??
                ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            let nextRoute: Route
            if username.isEmpty {
                nextRoute = .needUsername
            } else if photo.isEmpty {
                nextRoute = .needPhoto
            } else {
                nextRoute = .ready
            }

            if self.route != nextRoute {
                self.route = nextRoute
            }
        }
    }

    /// Persist the provided FCM token under users/{uid}/fcmTokens for multi-device support.
    func updateFCMTokenWith(_ token: String) {
        guard let uid = Auth.auth().currentUser?.uid, !token.isEmpty else {
            #if DEBUG
            print("[AuthManager] updateFCMTokenWith called without current user or empty token")
            #endif
            return
        }
        let fieldPath = "fcmTokens.\(token)"
        db.collection("users").document(uid).setData([
            fieldPath: FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true) { err in
            #if DEBUG
            if let err = err {
                print("[AuthManager] Failed to save FCM token: \(err)")
            } else {
                print("[AuthManager] Saved FCM token")
            }
            #endif
        }
    }

    /// Ask FCM for the current registration token and save it.
    func captureAndSaveCurrentFCMToken() {
        Messaging.messaging().token { [weak self] token, error in
            guard let self = self else { return }
            if error != nil {
                #if DEBUG
                print("[AuthManager] Error fetching FCM token")
                #endif
                return
            }
            guard let token = token, !token.isEmpty else {
                #if DEBUG
                print("[AuthManager] No FCM token available yet")
                #endif
                return
            }
            self.updateFCMTokenWith(token)
        }
    }

    /// Idempotent user container creation.
    private func ensureUserContainers(uid: String, email: String?) {
        db.collection("users").document(uid).setData([
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "email": email ?? ""
        ], merge: true)
        // Listings live under users/{uid}/listings/{listingId}; created when needed.
    }

    // MARK: - Apple Sign-In
    // Utilities
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: Array<Character> =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var rng = SystemRandomNumberGenerator()
                return UInt8.random(in: 0...255, using: &rng)
            }

            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    /// Main Apple Sign-In handler
    func handleAppleSignIn(result: ASAuthorization, completion: @escaping (Result<FirebaseAuth.User, Error>) -> Void) {
        guard let appleIDCredential = result.credential as? ASAuthorizationAppleIDCredential else {
            completion(.failure(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Apple credential"])))
            return
        }

        guard let nonce = currentNonce else {
            completion(.failure(NSError(domain: "AppleSignIn", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing nonce"])))
            return
        }

        guard let appleTokenData = appleIDCredential.identityToken,
              let idTokenString = String(data: appleTokenData, encoding: .utf8) else {
            completion(.failure(NSError(domain: "AppleSignIn", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unable to get id token"])))
            return
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )

        Auth.auth().signIn(with: credential) { authResult, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let user = authResult?.user else { return }
            self.ensureUserContainers(uid: user.uid, email: user.email)
            self.attachUserDocListener(uid: user.uid)
            self.captureAndSaveCurrentFCMToken()
            completion(.success(user))
        }
    }

    // Store nonce for Apple workflow
    private static var storedNonce: String?
    var currentNonce: String? {
        get { AuthManager.storedNonce }
        set { AuthManager.storedNonce = newValue }
    }

    func beginAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }
}
