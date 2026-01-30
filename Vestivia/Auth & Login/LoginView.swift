//
//  FakeLoginView.swift
//  Exchange
//
//  Created by William Hunsucker on 8/2/25.
//


import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import AuthenticationServices
import CryptoKit

func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset: Array<Character> =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length

    while remainingLength > 0 {
        let randoms: [UInt8] = (0 ..< 16).map { _ in
            var random: UInt8 = 0
            let error = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if error != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with code \(error)")
            }
            return random
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

func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashed = SHA256.hash(data: inputData)
    return hashed.compactMap { String(format: "%02x", $0) }.joined()
}

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var showUsernameSetup = false

    var body: some View {
        VStack(spacing: 0) {

            ZStack {
                LinearGradient(
                    colors: [Color.blue.opacity(0.85), Color.purple.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
                .clipShape(WaveShape())
                .ignoresSafeArea(edges: .top)

                Image("Whitelogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240) // increased from 120
                    .padding(.top, 20)
            }

            Text("Welcome, Please Sign In:")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 20)

            Spacer().frame(height: 12)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
            }

            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                    let nonce = randomNonceString()
                    request.nonce = sha256(nonce)
                    AuthManager.shared.currentNonce = nonce
                    #if DEBUG
                    print("🍏 Generated Apple nonce:", nonce)
                    #endif
                },
                onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        #if DEBUG
                        print("🍎 Apple Sign-In success: \(authorization)")
                        #endif
                        AuthManager.shared.handleAppleSignIn(result: authorization) { authResult in
                            switch authResult {
                            case .success(_):
                                if let uid = Auth.auth().currentUser?.uid {
                                    Task { await ensureUserDoc(uid: uid); self.isLoggedIn = true }
                                }
                            case .failure(let error):
                                errorMessage = error.localizedDescription
                            }
                        }
                    case .failure(let error):
                        #if DEBUG
                        print("❌ Apple Sign-In failed:", error.localizedDescription)
                        #endif
                        self.errorMessage = error.localizedDescription
                    }
                }
            )
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
            )
            .cornerRadius(22)
            .padding(.horizontal, 108)
            .padding(.top, 12)

            Button(action: {
                #if DEBUG
                print("🔵 Starting Google Sign-In…")
                #endif
                if let root = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                    .first?.rootViewController {
                    AuthManager.shared.signInWithGoogle(presenting: root) { result in
                        switch result {
                        case .success(_):
                            #if DEBUG
                            print("🔵 Google Sign-In success, checking user doc…")
                            #endif
                            if let uid = Auth.auth().currentUser?.uid {
                                Task {
                                    await ensureUserDoc(uid: uid)
                                    do {
                                        let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
                                        let usernameLower = (snap.data()?["usernameLower"] as? String)?
                                            .trimmingCharacters(in: .whitespacesAndNewlines)
                                        await MainActor.run {
                                            if let name = usernameLower, !name.isEmpty {
                                                self.isLoggedIn = true
                                            } else {
                                                self.showUsernameSetup = true
                                            }
                                        }
                                    } catch {
                                        await MainActor.run { self.showUsernameSetup = true }
                                    }
                                }
                            } else {
                                errorMessage = "Missing user id after Google sign-in. Please try again."
                            }
                        case .failure(let error):
                            #if DEBUG
                            print("❌ Google Sign-In failed:", error.localizedDescription)
                            #endif
                            errorMessage = error.localizedDescription
                        }
                    }
                } else {
                    errorMessage = "Unable to find a presenting view controller."
                }
            }) {
                Image("GoogleLogin")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding(.horizontal, 10)
            .padding(.top, 0)

            Spacer().frame(height: 40)

            ZStack {
                LinearGradient(
                    colors: [Color.purple.opacity(0.85), Color.blue.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .bottom)
                .clipShape(
                    WaveShape()
                        .rotation(Angle(degrees: 180))
                )
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .edgesIgnoringSafeArea(.top)
        .onAppear {
            #if DEBUG
            print("[LoginView] appeared, isLoggedIn =", isLoggedIn)
            #endif
        }
    }
    
    private func ensureUserDoc(uid: String) async {
        #if DEBUG
        print("🗂 ensureUserDoc called for uid:", uid)
        #endif
        let ref = Firestore.firestore().collection("users").document(uid)
        do {
            let snap = try await ref.getDocument()
            #if DEBUG
            print("🗂 ensureUserDoc snapshot exists:", snap.exists)
            #endif
            if !snap.exists {
                try await ref.setData([
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])
            }
        } catch {
            #if DEBUG
            print("[LoginView] ensureUserDoc error:", error.localizedDescription)
            #endif
        }
    }
}

struct CustomField: View {
    @Binding var text: String
    var icon: String
    var placeholder: String
    var isSecure: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.gray)
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.width * 0.5

        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: rect.height * 0.75))

        path.addQuadCurve(
            to: CGPoint(x: mid, y: rect.height * 0.85),
            control: CGPoint(x: rect.width * 0.25, y: rect.height * 0.95)
        )

        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.75),
            control: CGPoint(x: rect.width * 0.75, y: rect.height * 0.72)
        )

        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.closeSubpath()

        return path
    }
}

// MARK: - Preview
struct LoginView_Previews: PreviewProvider {
    @State static var loggedIn = false
    static var previews: some View {
        LoginView(isLoggedIn: $loggedIn)
            .previewDevice("iPhone 16 Pro")
    }
}
