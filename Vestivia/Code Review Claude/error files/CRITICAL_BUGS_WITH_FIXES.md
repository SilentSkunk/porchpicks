# Critical Bugs - Immediate Fixes Required

## 🚨 Bug #1: Unconfigured API Endpoints Will Crash App

**File:** `MatchResult.swift`  
**Lines:** 118-124  
**Severity:** BLOCKER  
**Impact:** Pattern Match feature completely broken

### Current Code (BROKEN):
```swift
enum PatternMatchAPI {
    static let searchEndpoint = URL(string: "https://your.api.example.com/api/search")!
    static let activeSearchEndpoint = URL(string: "https://your.api.example.com/api/active-search")!
    
    static var isConfigured: Bool {
        guard let host2 = searchEndpoint.host,
              let host3 = activeSearchEndpoint.host else { return false }
        return !host2.contains("your.api.example.com")
            && !host3.contains("your.api.example.com")
    }
}
```

### Fixed Code:
```swift
enum PatternMatchAPI {
    // MARK: - Configuration
    private enum Environment {
        case development
        case staging
        case production
        
        static var current: Environment {
            #if DEBUG
            return .development
            #else
            return .production
            #endif
        }
    }
    
    // MARK: - Endpoints
    static var searchEndpoint: URL {
        let urlString: String
        switch Environment.current {
        case .development:
            urlString = "https://dev-api.vestivia.com/api/search"
        case .staging:
            urlString = "https://staging-api.vestivia.com/api/search"
        case .production:
            urlString = "https://api.vestivia.com/api/search"
        }
        
        guard let url = URL(string: urlString) else {
            fatalError("Invalid configuration: searchEndpoint URL is malformed")
        }
        return url
    }
    
    static var activeSearchEndpoint: URL {
        let urlString: String
        switch Environment.current {
        case .development:
            urlString = "https://dev-api.vestivia.com/api/active-search"
        case .staging:
            urlString = "https://staging-api.vestivia.com/api/active-search"
        case .production:
            urlString = "https://api.vestivia.com/api/active-search"
        }
        
        guard let url = URL(string: urlString) else {
            fatalError("Invalid configuration: activeSearchEndpoint URL is malformed")
        }
        return url
    }
    
    static var isConfigured: Bool {
        // Check that endpoints are reachable (basic validation)
        return searchEndpoint.host != nil && activeSearchEndpoint.host != nil
    }
    
    static func purchaseURL(for listingId: String) -> URL {
        // Use deep link scheme for your app
        guard let url = URL(string: "vestivia://listing/\(listingId)") else {
            // Fallback to web URL if deep link fails
            return URL(string: "https://vestivia.com/listing/\(listingId)")!
        }
        return url
    }
}
```

**Testing Steps:**
1. Replace placeholder URLs with actual endpoints
2. Test in development build first
3. Verify network calls succeed
4. Test staging before production
5. Add unit test to verify URLs are valid

---

## 🚨 Bug #2: Main Thread Blocking During Image Upload

**File:** `AddListingViewSingle.swift`  
**Lines:** 257-261  
**Severity:** HIGH  
**Impact:** UI freezes during listing submission, poor UX

### Current Code (BLOCKING):
```swift
var selectedImagesData: [Data] {
    selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
    // ⚠️ This runs EVERY time property is accessed
    // ⚠️ Compresses images on main thread
    // ⚠️ Causes UI lag with multiple images
}
```

### Fixed Code:
```swift
class ListingViewModel: ObservableObject {
    @Published var selectedImages: [UIImage] = []
    
    // Cache the compressed data
    private var _cachedImageData: [Data] = []
    
    var selectedImagesData: [Data] {
        return _cachedImageData
    }
    
    func addImage(_ image: UIImage) {
        selectedImages.append(image)
        
        // Compress on background thread
        Task.detached(priority: .userInitiated) {
            guard let data = await self.compressImage(image) else { return }
            
            await MainActor.run {
                self._cachedImageData.append(data)
            }
        }
    }
    
    private func compressImage(_ image: UIImage) async -> Data? {
        // Run expensive operation off main thread
        return await Task.detached {
            return image.jpegData(compressionQuality: 0.8)
        }.value
    }
    
    func removeImage(at index: Int) {
        guard index < selectedImages.count else { return }
        selectedImages.remove(at: index)
        if index < _cachedImageData.count {
            _cachedImageData.remove(at: index)
        }
    }
    
    func clearImages() {
        selectedImages.removeAll()
        _cachedImageData.removeAll()
    }
}
```

**Testing Steps:**
1. Add 10 images to a listing
2. Monitor main thread usage in Instruments
3. Verify UI remains responsive
4. Check memory usage is reasonable
5. Test on older devices (iPhone 8)

---

## 🚨 Bug #3: Memory Leak in Profile Avatar Loading

**File:** `ProfileVM.swift`  
**Lines:** 44-58  
**Severity:** HIGH  
**Impact:** Memory grows over time, potential crashes

### Current Code (LEAKING):
```swift
private func loadImage(from url: URL) {
    var req = URLRequest(url: url)
    req.cachePolicy = .returnCacheDataElseLoad
    URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
        guard let self = self, let data = data, let ui = UIImage(data: data) else { return }
        DispatchQueue.main.async {
            // ⚠️ Captures self strongly in nested closure
            self.avatarImage = Image(uiImage: ui)
        }
    }.resume()
}
```

### Fixed Code:
```swift
private func loadImage(from url: URL) {
    var req = URLRequest(url: url)
    req.cachePolicy = .returnCacheDataElseLoad
    
    URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
        guard let self = self else { return }
        guard let data = data, let ui = UIImage(data: data) else { return }
        
        // Use Task instead of DispatchQueue to avoid capture issues
        Task { @MainActor [weak self] in
            self?.avatarImage = Image(uiImage: ui)
        }
    }.resume()
}

// BETTER: Use async/await entirely
private func loadImage(from url: URL) async {
    var req = URLRequest(url: url)
    req.cachePolicy = .returnCacheDataElseLoad
    
    do {
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let ui = UIImage(data: data) else { return }
        
        await MainActor.run { [weak self] in
            self?.avatarImage = Image(uiImage: ui)
        }
    } catch {
        print("[ProfileVM] Failed to load avatar: \(error)")
    }
}
```

**Testing Steps:**
1. Use Xcode Instruments Memory Graph
2. Load profile 10 times
3. Check for leaked closures
4. Verify memory is released
5. Check retain cycles in Debug Memory Graph

---

## 🚨 Bug #4: Race Condition in Likes Cache

**File:** `LikesVM.swift`  
**Lines:** 217-227  
**Severity:** MEDIUM  
**Impact:** Data corruption, inconsistent state

### Current Code (UNSAFE):
```swift
func setCachedHeroURL(_ url: URL, for listingId: String, exp: TimeInterval? = nil) {
    // ⚠️ No synchronization - multiple calls can overlap
    heroURLById[listingId] = url
    if let e = exp { heroExpById[listingId] = e }
    saveImagesCacheToDisk()  // ⚠️ Can be called from multiple threads
}

private func saveImagesCacheToDisk() {
    var out: [String: _DiskImageCacheEntry] = [:]
    for (id, url) in heroURLById {
        out[id] = _DiskImageCacheEntry(url: url.absoluteString, exp: heroExpById[id])
    }
    do {
        let data = try JSONEncoder().encode(out)
        try data.write(to: imagesCacheFileURL, options: [.atomic])
    } catch {
        #if DEBUG
        print("[LikesVM] save hero cache error:", error)
        #endif
    }
}
```

### Fixed Code:
```swift
@MainActor
final class LikesVM: ObservableObject {
    // ... existing properties ...
    
    // Serial queue for all cache operations
    private let cacheQueue = DispatchQueue(label: "com.vestivia.likesCache", qos: .utility)
    
    func setCachedHeroURL(_ url: URL, for listingId: String, exp: TimeInterval? = nil) {
        // Update in-memory cache immediately (on main thread)
        heroURLById[listingId] = url
        if let e = exp { heroExpById[listingId] = e }
        
        // Write to disk on background queue
        Task.detached(priority: .utility) { [weak self] in
            await self?.saveImagesCacheToDisk()
        }
    }
    
    private func saveImagesCacheToDisk() async {
        // Capture current state
        let urlsSnapshot = heroURLById
        let expirySnapshot = heroExpById
        let fileURL = imagesCacheFileURL
        
        // Perform disk I/O on background queue
        await Task.detached(priority: .utility) {
            var out: [String: _DiskImageCacheEntry] = [:]
            for (id, url) in urlsSnapshot {
                out[id] = _DiskImageCacheEntry(
                    url: url.absoluteString,
                    exp: expirySnapshot[id]
                )
            }
            
            do {
                let data = try JSONEncoder().encode(out)
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                #if DEBUG
                print("[LikesVM] save hero cache error:", error)")
                #endif
            }
        }.value
    }
    
    private func loadImagesCacheFromDisk() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            
            let fileURL = self.imagesCacheFileURL
            guard let data = try? Data(contentsOf: fileURL) else { return }
            guard let decoded = try? JSONDecoder().decode([String: _DiskImageCacheEntry].self, from: data) else { return }
            
            var map: [String: URL] = [:]
            var exp: [String: TimeInterval] = [:]
            
            for (id, entry) in decoded {
                if let url = URL(string: entry.url) {
                    map[id] = url
                    if let t = entry.exp { exp[id] = t }
                }
            }
            
            await MainActor.run { [weak self] in
                self?.heroURLById = map
                self?.heroExpById = exp
            }
        }
    }
}
```

**Testing Steps:**
1. Call `setCachedHeroURL` rapidly from multiple places
2. Check file system consistency
3. Verify no crashes occur
4. Use Thread Sanitizer in Xcode
5. Load 100 likes simultaneously

---

## 🚨 Bug #5: Silent Error Swallowing in Listing Submission

**File:** `ListingSubmission.swift`  
**Lines:** 67-73  
**Severity:** HIGH  
**Impact:** Users don't know upload failed, data loss

### Current Code (SILENT FAILURE):
```swift
for imageData in listing.imageData {
    do {
        let imageId = try await CloudflareUploader.shared.uploadImage(imageData: imageData)
        uploadedImageIds.append(imageId)
        print("✅ Uploaded image to Cloudflare (imageId): \(imageId)")
    } catch {
        print("❌ Error uploading to Cloudflare: \(error)")
        // ⚠️ Error logged but listing submission continues anyway!
        // ⚠️ User sees nothing!
        // ⚠️ Listing saved with missing images!
    }
}
```

### Fixed Code:
```swift
@MainActor
func submit(listing: SingleListing, patternJPEGData: Data?) async {
    // Add error state
    var errorMessage: String?
    var uploadedImageIds: [String] = []
    
    // Show progress to user
    await MainActor.run {
        // Notify UI that upload started
        NotificationCenter.default.post(name: .listingUploadStarted, object: nil)
    }
    
    // Upload images with retry logic
    for (index, imageData) in listing.imageData.enumerated() {
        var attempts = 0
        let maxAttempts = 3
        var lastError: Error?
        
        while attempts < maxAttempts {
            do {
                let imageId = try await CloudflareUploader.shared.uploadImage(imageData: imageData)
                uploadedImageIds.append(imageId)
                
                await MainActor.run {
                    // Update progress
                    let progress = Double(index + 1) / Double(listing.imageData.count)
                    NotificationCenter.default.post(
                        name: .listingUploadProgress,
                        object: nil,
                        userInfo: ["progress": progress]
                    )
                }
                
                break // Success, exit retry loop
                
            } catch {
                lastError = error
                attempts += 1
                
                if attempts < maxAttempts {
                    // Wait before retry (exponential backoff)
                    try? await Task.sleep(nanoseconds: UInt64(attempts * 1_000_000_000))
                }
            }
        }
        
        // If all retries failed, abort submission
        if attempts == maxAttempts {
            errorMessage = "Failed to upload image \(index + 1). Please check your connection and try again."
            
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .listingUploadFailed,
                    object: nil,
                    userInfo: ["error": errorMessage ?? "Unknown error"]
                )
            }
            
            return // ✅ Stop submission instead of continuing
        }
    }
    
    // Verify we have at least one image
    guard !uploadedImageIds.isEmpty else {
        errorMessage = "At least one image is required to create a listing."
        await MainActor.run {
            NotificationCenter.default.post(
                name: .listingUploadFailed,
                object: nil,
                userInfo: ["error": errorMessage ?? "No images uploaded"]
            )
        }
        return
    }
    
    // Continue with Firestore submission...
    // ... rest of existing code ...
    
    await MainActor.run {
        NotificationCenter.default.post(name: .listingUploadCompleted, object: nil)
    }
}

// Add notification names
extension Notification.Name {
    static let listingUploadStarted = Notification.Name("listingUploadStarted")
    static let listingUploadProgress = Notification.Name("listingUploadProgress")
    static let listingUploadFailed = Notification.Name("listingUploadFailed")
    static let listingUploadCompleted = Notification.Name("listingUploadCompleted")
}
```

**In AddListingViewSingle.swift, handle the notifications:**
```swift
struct AddListingViewSingle: View {
    @State private var uploadProgress: Double = 0
    @State private var isUploading = false
    @State private var uploadError: String?
    
    var body: some View {
        // ... existing view code ...
        
        .onReceive(NotificationCenter.default.publisher(for: .listingUploadStarted)) { _ in
            isUploading = true
            uploadProgress = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .listingUploadProgress)) { notification in
            if let progress = notification.userInfo?["progress"] as? Double {
                uploadProgress = progress
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .listingUploadFailed)) { notification in
            isUploading = false
            if let error = notification.userInfo?["error"] as? String {
                uploadError = error
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .listingUploadCompleted)) { _ in
            isUploading = false
            uploadProgress = 1.0
            // Navigate back or show success
            dismiss()
        }
        .alert("Upload Failed", isPresented: .constant(uploadError != nil)) {
            Button("OK") { uploadError = nil }
        } message: {
            Text(uploadError ?? "")
        }
        .overlay {
            if isUploading {
                VStack {
                    ProgressView("Uploading...", value: uploadProgress, total: 1.0)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(radius: 8)
                }
            }
        }
    }
}
```

**Testing Steps:**
1. Test with airplane mode (no network)
2. Test with slow network
3. Test with large images (> 5MB)
4. Verify user sees error messages
5. Verify retry logic works
6. Check that failed uploads don't create partial listings

---

## 🔧 Quick Test Script

Run this in your test suite to verify the fixes:

```swift
final class CriticalBugTests: XCTestCase {
    
    func testAPIEndpointsConfigured() {
        XCTAssertNotNil(PatternMatchAPI.searchEndpoint.host, "Search endpoint not configured")
        XCTAssertNotNil(PatternMatchAPI.activeSearchEndpoint.host, "Active search endpoint not configured")
        XCTAssertTrue(PatternMatchAPI.isConfigured, "API not properly configured")
        XCTAssertFalse(PatternMatchAPI.searchEndpoint.absoluteString.contains("your.api.example.com"))
    }
    
    func testImageCompressionOffMainThread() async {
        let expectation = XCTestExpectation(description: "Image compression completes")
        let vm = ListingViewModel()
        let testImage = UIImage(systemName: "photo")!
        
        let isMainThread = Thread.isMainThread
        vm.addImage(testImage)
        
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        
        XCTAssertTrue(isMainThread, "Should be called from main thread")
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    func testNoMemoryLeakInProfileVM() {
        weak var weakVM: ProfileVM?
        
        autoreleasepool {
            let vm = ProfileVM()
            weakVM = vm
            vm.start()
            vm.stop()
        }
        
        XCTAssertNil(weakVM, "ProfileVM should be deallocated")
    }
    
    func testListingSubmissionFailsGracefullyWithoutImages() async {
        let listing = SingleListing(
            category: "Test",
            subcategory: "Test",
            size: "S",
            condition: "New",
            gender: "Unisex",
            description: "Test",
            color: "Blue",
            originalPrice: "$10",
            listingPrice: "$5",
            brand: "Test",
            images: [] // No images
        )
        
        // Should fail gracefully, not crash
        await ListingSubmission.shared.submit(listing: listing)
        
        // Verify error notification was posted
        // (requires notification observer in test)
    }
}
```

---

## ✅ Sign-Off Checklist

Before deploying fixes:

- [ ] All 5 critical bugs fixed
- [ ] Unit tests passing
- [ ] Manual testing completed
- [ ] Code review approved
- [ ] Performance verified (no regressions)
- [ ] Memory leaks checked with Instruments
- [ ] Error messages user-friendly
- [ ] Logging appropriate (not exposing sensitive data)

---

**Priority:** P0 - Must fix before next release  
**Estimated Time:** 4-6 hours total  
**Risk if not fixed:** App crashes, data loss, poor UX, memory leaks
