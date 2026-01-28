import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct ProfileImageSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var isUploading = false
    @State private var error: String?

    /// Resize and compress to keep uploads snappy (~<=2MB).
    private func processedJPEGData(from data: Data, maxDimension: CGFloat = 1200, quality: CGFloat = 0.85) -> Data? {
        guard let original = UIImage(data: data) else { return nil }
        let size = original.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let scaled = renderer.image { _ in
            original.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return scaled.jpegData(compressionQuality: quality)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Add a profile photo")
                    .font(.title2).bold()

                ZStack {
                    if let imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 140, height: 140)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 140, height: 140)
                            .overlay(Image(systemName: "person.fill").font(.largeTitle))
                    }
                }
                .padding(.top, 8)

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Text("Choose Photo")
                }
                .onChange(of: selectedItem) { _, newItem in
                    Task {
                        guard let item = newItem else { return }
                        if let raw = try? await item.loadTransferable(type: Data.self),
                           let jpeg = processedJPEGData(from: raw) {
                            await MainActor.run {
                                self.imageData = jpeg
                                // Clear the selection so PhotosPicker won't re-fire and we won't accidentally re-upload.
                                self.selectedItem = nil
                            }
                        }
                    }
                }

                if let error {
                    Text(error).foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await uploadAndFinish() }
                } label: {
                    if isUploading {
                        ProgressView()
                    } else {
                        Text("Finish").bold()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(imageData == nil || isUploading)

                Text("You can change this later in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
        }
    }

    private func uploadAndFinish() async {
        // Re-entrancy guard to prevent duplicate uploads / duplicate Storage requests
        if isUploading { return }
        
        guard
            let uid = Auth.auth().currentUser?.uid,
            let data = imageData
        else {
            await MainActor.run { self.error = "Missing user or image." }
            return
        }
        guard let uiImage = UIImage(data: data) else { await MainActor.run { self.error = "Image decode failed." }; return }

        await MainActor.run { isUploading = true }
        defer { Task { await MainActor.run { isUploading = false } } }

        do {
            // Upload to Storage and get a public URL string
            let urlString = try await ProfilePhotoService.upload(image: uiImage, for: uid)
            guard !urlString.isEmpty else {
                await MainActor.run { self.error = "Upload succeeded, but no URL was returned." }
                return
            }

            // Save to Firestore user doc (merge)
            try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .setData(["photoURL": urlString,
                          "updatedAt": FieldValue.serverTimestamp()],
                         merge: true)

            // Hard exit to the main app; bypasses any stacked onboarding views.
            await MainActor.run {
                UserDefaults.standard.set(true, forKey: "onboardingComplete")
                forceExitToMain()
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
}

@MainActor
private func forceExitToMain() {
    guard let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive }),
          let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
        // Fallback: search all foreground-active window scenes for a key window
        let allScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in allScenes where scene.activationState == .foregroundActive {
            if let win = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                win.rootViewController = UIHostingController(rootView: MainTabView(isLoggedIn: .constant(true)))
                win.makeKeyAndVisible()
                return
            }
        }
        return
    }
    window.rootViewController = UIHostingController(rootView: MainTabView(isLoggedIn: .constant(true)))
    window.makeKeyAndVisible()
}
