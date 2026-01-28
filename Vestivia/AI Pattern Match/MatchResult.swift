//
//  PatternMatchView.swift
//  Exchange
//
//  Created by You on 8/27/25.
//

import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import FirebaseStorage
import FirebaseAuth
import FirebaseFirestore

// MARK: - UIImage resize helper
extension UIImage {
    /// Returns a new image scaled to `target` using UIGraphicsImageRenderer.
    func lp_resized(to target: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

// Reuse profile-style image prep for pattern photos by extending your existing service
extension ProfilePhotoService {
    /// Prepare a square JPEG with normalized orientation, SDR rendering, and size cap.
    /// Returns the resized UIImage (for preview/embedding) and JPEG Data (for upload).
    public static func prepareSquareJPEG(_ image: UIImage, target: CGFloat = 512, maxBytes: Int = 300 * 1024) -> (uiImage: UIImage, data: Data) {
        let norm = _normalized(image)
        let square = _squareResized(norm, target: target)
        let data = _jpegDataUnderLimit(square, maxBytes: maxBytes)
        return (square, data)
    }

    // MARK: - Local helpers (scoped to this extension to avoid naming collisions)
    private static func _normalized(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        if #available(iOS 12.0, *) { format.preferredRange = .standard }
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func _squareResized(_ image: UIImage, target: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let side = min(w, h)
        let cropOrigin = CGPoint(x: (w - side) / 2, y: (h - side) / 2)
        let cropRect = CGRect(origin: cropOrigin, size: CGSize(width: side, height: side))

        // Crop to square (SDR)
        let formatCrop = UIGraphicsImageRendererFormat()
        formatCrop.scale = image.scale
        formatCrop.opaque = true
        if #available(iOS 12.0, *) { formatCrop.preferredRange = .standard }
        let squared = UIGraphicsImageRenderer(size: cropRect.size, format: formatCrop).image { _ in
            image.draw(at: CGPoint(x: -cropOrigin.x, y: -cropOrigin.y))
        }

        // Resize to target (SDR)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        if #available(iOS 12.0, *) { format.preferredRange = .standard }
        let size = CGSize(width: target, height: target)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            squared.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func _jpegDataUnderLimit(_ image: UIImage, maxBytes: Int) -> Data {
        var q: CGFloat = 0.8
        var data = image.jpegData(compressionQuality: q) ?? Data()
        if data.count <= maxBytes { return data }
        var low: CGFloat = 0.3, high: CGFloat = 0.8
        for _ in 0..<6 {
            q = (low + high) / 2
            if let d = image.jpegData(compressionQuality: q) {
                data = d
                if d.count > maxBytes { high = q } else { low = q }
            }
        }
        return data
    }
}

// MARK: - Models

struct MatchResult: Identifiable, Decodable {
    let id: String           // listingId
    let title: String
    let price: Double
    let brand: String?
    let size: String?
    let score: Double
    let imageUrl: String
}

struct SearchResponse: Decodable {
    let results: [MatchResult]
}



struct CreateActiveSearchResponse: Decodable {
    let ok: Bool
    let searchId: String?
}

// MARK: - Local cache (compatible with PatternsView)
// Uses the same keys and shape as PatternEntry (id, brand, path)
private struct _CachedPatternEntry: Codable, Hashable {
    let id: String
    let brand: String
    let path: String
}

private enum _LocalActivePatternsStoreCompat {
    static func cacheKey(for uid: String) -> String { "active_patterns_\(uid)" }
    static func hydratedKey(for uid: String) -> String { "active_patterns_hydrated_\(uid)" }

    static func load(uid: String) -> [_CachedPatternEntry] {
        let key = cacheKey(for: uid)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([_CachedPatternEntry].self, from: data)) ?? []
    }

    static func save(uid: String, items: [_CachedPatternEntry]) {
        let key = cacheKey(for: uid)
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func upsert(uid: String, entry: _CachedPatternEntry) {
        var current = load(uid: uid)
        if let idx = current.firstIndex(where: { $0.id == entry.id && $0.brand == entry.brand }) {
            current[idx] = entry
        } else {
            current.insert(entry, at: 0)
        }
        save(uid: uid, items: current)
    }

    static func markHydrated(uid: String) {
        UserDefaults.standard.set(true, forKey: hydratedKey(for: uid))
    }
}

// MARK: - Config (set your endpoints)

enum PatternMatchAPI {
    /// POST { imageId, filters: {brand, size} } → { results: [...] }
    static let searchEndpoint       = URL(string: "https://your.api.example.com/api/search")!

    /// POST { imageId, filters: {brand, size} } → { ok: true, searchId }
    static let activeSearchEndpoint = URL(string: "https://your.api.example.com/api/active-search")!

    /// Check if endpoints have been configured (not left as placeholders)
    static var isConfigured: Bool {
        guard let host2 = searchEndpoint.host,
              let host3 = activeSearchEndpoint.host else { return false }
        return !host2.contains("your.api.example.com")
            && !host3.contains("your.api.example.com")
    }

    /// Build your purchase deeplink/web URL
    static func purchaseURL(for listingId: String) -> URL {
        URL(string: "yourapp://listing/\(listingId)")!
    }
}



// MARK: - ViewModel

@MainActor
final class PatternMatchViewModel: ObservableObject {
    @Published var image: UIImage?
    @Published var isUploading = false
    @Published var isSearching = false
    @Published var uploadProgress: Double = 0
    @Published var imageId: String?
    @Published var results: [MatchResult] = []
    @Published var errorMessage: String?
    @Published var infoMessage: String?

#if DEBUG
    @Published var debugLog: [String] = []
#endif

    private func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[PatternMatch] \(stamp) — \(message)"
        print(line)
#if DEBUG
        debugLog.append(line)
#endif
    }

    // REQUIRED filters
    @Published var filterBrand: String = ""
    @Published var filterSize: String  = ""

    // MARK: - Public actions

    func submit() {
        Task {
            errorMessage = nil
            infoMessage = nil
            results = []
            log("Submit tapped. brand=\(filterBrand), size=\(filterSize)")

            guard let src = image else {
                errorMessage = "Please take or choose a photo first."
                return
            }
            let prepared = ProfilePhotoService.prepareSquareJPEG(src, target: 512, maxBytes: 300 * 1024)
            let img = prepared.uiImage
            let data = prepared.data
            log("Prepared image: \(Int(img.size.width))x\(Int(img.size.height)), data=\(data.count) bytes")
            // Require brand & size
            guard !filterBrand.isEmpty, !filterSize.isEmpty else {
                errorMessage = "Please enter brand and size."
                return
            }

            do {
                log("Uploading to Firebase Storage under brand folder…")
                isUploading = true; uploadProgress = 0

                let brandKey = filterBrand.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased().replacingOccurrences(of: " ", with: "-")
                let searchId = UUID().uuidString.lowercased()

                // Ensure user
                guard let uid = Auth.auth().currentUser?.uid else {
                    isUploading = false
                    errorMessage = "Not signed in."
                    return
                }

                // Upload to Storage (primary, brand-first)
                let pathPrimary = "pattern_queries/\(brandKey)/\(uid)/\(searchId).jpg"
                let ref = Storage.storage().reference(withPath: pathPrimary)
                let meta = StorageMetadata(); meta.contentType = "image/jpeg"
                _ = try await ref.putDataAsync(data, metadata: meta)
                self.uploadProgress = 0.6
                log("Upload complete. storagePathPrimary=\(pathPrimary)")

                // Mirror to per-user path for easy listing in UI (upload a small thumbnail)
                let pathUser = "users_active_patterns/\(uid)/\(brandKey)/\(searchId).jpg"
                do {
                    // Build a smaller thumbnail from the prepared 512 image
                    let thumb = img.lp_resized(to: CGSize(width: 128, height: 128))
                    guard let thumbData = thumb.jpegData(compressionQuality: 0.70) else {
                        throw NSError(domain: "PatternMatch", code: -10, userInfo: [NSLocalizedDescriptionKey: "Failed to encode thumbnail JPEG"])
                    }
                    let thumbMeta = StorageMetadata(); thumbMeta.contentType = "image/jpeg"

                    let ref2 = Storage.storage().reference(withPath: pathUser)
                    _ = try await ref2.putDataAsync(thumbData, metadata: thumbMeta)
                    log("Mirror upload (thumbnail) complete. storagePathUser=\(pathUser)")
                } catch {
                    log("Mirror upload failed: \(error.localizedDescription)")
                }

                // Finish progress
                self.uploadProgress = 1.0
                isUploading = false

                // ✅ Update local cache so PatternsView shows instantly
                let cacheEntry = _CachedPatternEntry(id: searchId, brand: brandKey, path: pathUser)
                _LocalActivePatternsStoreCompat.upsert(uid: uid, entry: cacheEntry)
                _LocalActivePatternsStoreCompat.markHydrated(uid: uid)

                // Persist minimal metadata doc for this query (for UI listing)
                do {
                    try await Firestore.firestore()
                        .collection("active_searches").document(uid)
                        .collection("items").document(searchId)
                        .setData([
                            "brandLower": brandKey,
                            "size": filterSize,
                            "storagePathPrimary": pathPrimary,
                            "storagePathUser": pathUser,
                            "createdAt": FieldValue.serverTimestamp()
                        ], merge: true)
                } catch {
                    log("Warning: failed to write active_searches doc: \(error.localizedDescription)")
                }

                self.infoMessage = "Your pattern is saved. We'll notify you when we find a match."
                self.results = []
                return
            } catch {
                isUploading = false
                let nsErr = error as NSError
                log("Error: \(nsErr.domain) code=\(nsErr.code) — \(nsErr.localizedDescription)")
                if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCannotFindHost {
                    self.errorMessage = "Cannot reach search API. Check your internet connection and PatternMatchAPI URLs."
                } else {
                    self.errorMessage = nsErr.localizedDescription
                }
            }
        }
    }

    // MARK: - Networking


    private func search(usingFirebasePath path: String) async throws {
        isSearching = true
        log("POST /search")
        defer { isSearching = false }

        var req = URLRequest(url: PatternMatchAPI.searchEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "firebasePath": path,
            "filters": [
                "brand": filterBrand,
                "size":  filterSize
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        if let body = req.httpBody, let bodyStr = String(data: body, encoding: .utf8) { log("search payload: \(bodyStr)") }

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse { log("search status=\(http.statusCode)") }
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Search", code: 5, userInfo: [NSLocalizedDescriptionKey: "Search failed"])
        }
        let parsed = try JSONDecoder().decode(SearchResponse.self, from: data)
        log("search results=\(parsed.results.count)")
        self.results = parsed.results
    }

    @discardableResult
    private func createActiveSearch(firebasePath path: String) async throws -> CreateActiveSearchResponse {
        log("POST /active-search")
        var req = URLRequest(url: PatternMatchAPI.activeSearchEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "firebasePath": path,
            "filters": [
                "brand": filterBrand,
                "size":  filterSize
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        if let body = req.httpBody, let bodyStr = String(data: body, encoding: .utf8) { log("active-search payload: \(bodyStr)") }

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse { log("active-search status=\(http.statusCode)") }
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "ActiveSearch", code: 6, userInfo: [NSLocalizedDescriptionKey: "Could not create active search"])
        }
        return try JSONDecoder().decode(CreateActiveSearchResponse.self, from: data)
    }
}

// MARK: - PatternsView/PatternsListVM

// ... (rest of file unchanged)

// MARK: - PatternsView

// (Assume this is where PatternsListVM is defined, as per instructions.)

// PatternsListVM (snippet for robust loader, extension, and logging)
// Please integrate this into your PatternsListVM class.

// Example:
// @MainActor
// class PatternsListVM: ObservableObject { ... }

// --- PATCH: robust loader, fetchAndStore, extension normalization, improved logging ---

// 1) In load(forceRemote:), make loader more robust and always fetch remote if cache is empty:
// (Find and replace the relevant block in your PatternsListVM)
/*
    // 1) Always show cache immediately
    let cached = LocalActivePatternsStore.load(uid: uid)
    self.items = cached

    // 2) Decide whether to hit remote
    let needsHydrate = !LocalActivePatternsStore.isHydrated(uid: uid)
    guard forceRemote || needsHydrate else { return }
*/

// Replace with:
/*
    // 1) Always show cache immediately
    let cached = LocalActivePatternsStore.load(uid: uid)
    self.items = cached

    // 2) Decide whether to hit remote
    let needsHydrate = !LocalActivePatternsStore.isHydrated(uid: uid)
    let cacheIsEmpty = cached.isEmpty
    // If cache is empty, always fetch; also fetch when forced or hydration needed
    guard !(forceRemote || needsHydrate || cacheIsEmpty) else {
        await self.fetchAndStore(uid: uid)
        return
    }
*/

// 2) Add a helper fetchAndStore(uid:) in PatternsListVM:
/*
    private func fetchAndStore(uid: String) async {
        self.isLoading = true
        do {
            let fresh = try await fetchRemote(uid: uid)
            self.items = fresh
            LocalActivePatternsStore.save(uid: uid, items: fresh)
            LocalActivePatternsStore.markHydrated(uid: uid)
            self.isLoading = false
        } catch {
            self.error = error.localizedDescription
            self.isLoading = false
        }
    }
*/

// 3) In refresh(), make sure it calls load(forceRemote: true)
// (If already matches, leave as-is.)

// 4) In fetchRemote(uid:), update the inner file loop to normalize extensions and log:
/*
        for fileRef in brandResult.items {
            let file = fileRef.name // e.g. 123.jpg / 123.jpeg / 123.png / 123.webp
            var id = file
            for ext in [".jpg", ".jpeg", ".png", ".webp"] {
                if id.lowercased().hasSuffix(ext) { id = String(id.dropLast(ext.count)) }
            }
            let path = "users_active_patterns/\(uid)/\(brand)/\(file)"
            let url = try? await fileRef.downloadURL()
            collected.append(PatternEntry(id: id, brand: brand, path: path, thumbnailURL: url))
        }
        print("[PatternsListVM] brand=\(brand) items=\(brandResult.items.count)")
*/

// 5) After getting top-level prefixes, log the count:
/*
        let brandFolders = top.prefixes
        print("[PatternsListVM] found brand folders: \(brandFolders.count)")
        if brandFolders.isEmpty {
            self.isLoading = false
            return
        }
*/

// MARK: - View

struct HeroPlaceholder: View {
    var body: some View {
        VStack {
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundColor(.blue)
            Text("AI Pattern Match")
                .font(.headline)
                .foregroundColor(.primary)
            Text("Find similar patterns with a photo")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


struct PatternMatchView: View {
    @StateObject private var vm = PatternMatchViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode

    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var showHowTo = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                header

                // Image preview
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 280)

                    if let ui = vm.image {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("Take a photo or choose from library")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .contentShape(Rectangle())

                // Buttons row
                HStack {
                    Button {
                        showingCamera = true
                    } label: {
                        label(icon: "camera.fill", text: "Take Photo")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showingLibrary = true
                    } label: {
                        label(icon: "photo.fill.on.rectangle.fill", text: "Upload Photo")
                    }
                    .buttonStyle(.bordered)
                }

                // Filters (required)
                filterSection

                // Submit
                Button(action: vm.submit) {
                    HStack(spacing: 8) {
                        if vm.isUploading || vm.isSearching { ProgressView().tint(.white) }
                        Text(vm.isUploading ? "Uploading..." : vm.isSearching ? "Searching..." : "Find Matches")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    showHowTo ||
                    vm.image == nil ||
                    vm.isUploading ||
                    vm.isSearching ||
                    vm.filterBrand.isEmpty ||
                    vm.filterSize.isEmpty
                )

                // Upload progress
                if vm.isUploading {
                    ProgressView(value: vm.uploadProgress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                }

                // Auto-watch info blurb
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bell.badge.fill").foregroundColor(.blue)
                    Text("We’ll quickly search current listings and automatically keep an active watch for new listings that look similar. You’ll be notified when something close appears.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )

                // Results
                if !vm.results.isEmpty {
                    resultsSection
                }

#if true
                if let err = vm.errorMessage {
                    Text(err).foregroundStyle(.red).font(.footnote).padding(.top, 6)
                }
                if let msg = vm.infoMessage {
                    Text(msg)
                        .foregroundStyle(.green)
                        .font(.footnote)
                        .padding(.top, 6)
                }
#else
                if let err = vm.errorMessage {
                    Text(err).foregroundStyle(.red).font(.footnote).padding(.top, 6)
                }
#endif
#if DEBUG
                if !vm.debugLog.isEmpty {
                    DisclosureGroup("Debug") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(vm.debugLog.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.caption2).textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                    }
                    .padding(.top, 8)
                }
#endif
            }
            .padding()
        }
        .sheet(isPresented: $showingLibrary) {
            PhotoPicker(image: $vm.image)
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker(image: $vm.image)
        }
        .sheet(isPresented: $showHowTo) {
            PatternHowToSheet {
                showHowTo = false
            }
            .interactiveDismissDisabled(true)
        }
        .navigationTitle("AI Pattern Match")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                }
            }
        }
       .onChange(of: vm.image) { _, newValue in
            if newValue != nil {
                vm.submit() // (optional) remove if you don't want auto-submit on pick
                // Or just log:
                // if let img = newValue { vm.log("Image selected: \(Int(img.size.width))x\(Int(img.size.height))") }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI Pattern Match").font(.title2).bold()
            Text("Snap or upload a pattern. We’ll search current listings using your brand and size and automatically keep an active watch for new matches.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Results").font(.headline)
            ForEach(vm.results) { r in
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: r.imageUrl)) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground))
                                ProgressView()
                            }
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemBackground))
                                Image(systemName: "photo").foregroundColor(.secondary)
                            }
                        @unknown default:
                            Color.clear
                        }
                    }
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.title).font(.subheadline).bold().lineLimit(1)
                        Text("\(r.brand ?? "—") · \(r.size ?? "—")").font(.footnote).foregroundStyle(.secondary)
                        Text(String(format: "$%.2f", r.price)).font(.subheadline)
                        ProgressView(value: min(max(r.score, 0), 1))
                            .progressViewStyle(.linear)
                            .tint(.green)
                        Text("Similarity \(Int((min(max(r.score, 0), 1))*100))%")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link(destination: PatternMatchAPI.purchaseURL(for: r.id)) {
                        Image(systemName: "cart.fill")
                            .padding(10)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Filters (required)").font(.headline)
            HStack {
                TextField("Brand", text: $vm.filterBrand)
                    .textFieldStyle(.roundedBorder)
                TextField("Size", text: $vm.filterSize)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
        }
    }

    private func label(icon: String, text: String) -> some View {
        HStack {
            Image(systemName: icon)
            Text(text)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Photo Picker (Library)

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                DispatchQueue.main.async {
                    self.parent.image = image as? UIImage
                }
            }
        }
    }
}

// MARK: - Camera Picker (Capture)

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .rear
        picker.allowsEditing = true // allows quick center-cropping
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)
            let img = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            DispatchQueue.main.async { self.parent.image = img }
        }
    }
}

// MARK: - PatternHowToSheet

struct PatternHowToSheet: View {
    let onContinue: () -> Void

    init(onContinue: @escaping () -> Void) { self.onContinue = onContinue }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("How to take the best pattern photo")
                        .font(.title3).bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Center the fabric, fill the frame, avoid glare. See examples below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                Image("pattern_bad")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.red)
                                    .shadow(radius: 1)
                                    .padding(6)
                            }
                            Text("Too far / angled / glare")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        VStack(spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                Image("pattern_good")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.green)
                                    .shadow(radius: 1)
                                    .padding(6)
                            }
                            Text("Centered / close / no glare")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Fill the frame with the pattern", systemImage: "viewfinder")
                        Label("Hold the phone parallel to the fabric", systemImage: "rectangle.portrait")
                        Label("Avoid glare and harsh shadows", systemImage: "sun.max")
                        Label("Use soft light (window or shade)", systemImage: "light.max")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("I understand — Continue", action: onContinue)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Pattern Tips")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
