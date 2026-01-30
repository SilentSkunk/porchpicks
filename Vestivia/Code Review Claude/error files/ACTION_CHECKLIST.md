# Code Review Action Checklist

## 🔥 CRITICAL - Fix Immediately (Before Next Release)

- [ ] **Configure API Endpoints** (MatchResult.swift:118-124)
  - Replace `https://your.api.example.com` with actual endpoints
  - Test pattern match feature end-to-end
  - Add environment configuration (dev/staging/prod)

- [ ] **Fix Force Unwrapped URLs** (Multiple files)
  - MatchResult.swift lines 121, 124
  - PatternMatchAPI.purchaseURL line 132
  - Use `guard let` or provide better defaults

- [ ] **Add User Error Messages** (MatchResult.swift, ListingSubmission.swift)
  - Display upload failures to users
  - Show network errors with retry options
  - Add error messages to all async operations

---

## ⚠️ HIGH PRIORITY - Fix This Week

### Performance Fixes

- [ ] **Move Disk I/O Off Main Thread**
  - LikesVM.swift:217 `saveImagesCacheToDisk()`
  - LikesCacheFile.swift:54 `save()`
  - ProfilePhotoService.swift:52 `saveToCache()`
  
  ```swift
  // Quick fix template:
  Task.detached(priority: .background) {
      try? data.write(to: url, options: [.atomic])
  }
  ```

- [ ] **Fix Thumbnail Encoding** (AddListingViewSingle.swift:257)
  ```swift
  // Replace computed property with cached version
  private var _cachedImageData: [Data] = []
  ```

### Memory Leaks

- [ ] **Fix Closure Captures** (ProfileVM.swift:44-58)
  ```swift
  // Add [weak self] to nested URLSession closure
  URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
  ```

- [ ] **Fix LikesVM Listener** (LikesVM.swift:74)
  - Ensure listener is properly removed in deinit
  - Add [weak self] to snapshot listener

### Input Validation

- [ ] **Add Price Validation** (AddListingViewSingle.swift)
  ```swift
  func isValidPrice(_ price: String) -> Bool {
      let cleaned = price.filter { "0123456789.".contains($0) }
      return Double(cleaned) != nil && Double(cleaned)! > 0
  }
  ```

- [ ] **Add Description Length Limit**
  ```swift
  .onChange(of: viewModel.description) { newValue in
      if newValue.count > 1000 {
          viewModel.description = String(newValue.prefix(1000))
      }
  }
  ```

---

## 📅 MEDIUM PRIORITY - Fix This Sprint

### Loading States

- [ ] **Add Loading to PatternsView** (PatternsView.swift:56-68)
  ```swift
  if vm.isLoading {
      ProgressView("Loading patterns...")
  } else if vm.items.isEmpty {
      EmptyStateView()
  }
  ```

- [ ] **Add Loading to SellerProfileView** (SellerProfileView.swift:67)
  - Show skeleton screens while loading
  - Add pull-to-refresh indicators

### Error Handling

- [ ] **Consistent Error Display** (All ViewModels)
  ```swift
  @Published var errorMessage: String?
  
  .alert(item: $errorMessage) { message in
      Alert(title: Text("Error"), message: Text(message))
  }
  ```

- [ ] **Add Retry Logic** (CloudflareUploader.swift, ListingSubmission.swift)
  ```swift
  func uploadWithRetry(maxRetries: Int = 3) async throws {
      for attempt in 1...maxRetries {
          do {
              return try await upload()
          } catch {
              if attempt == maxRetries { throw error }
              try await Task.sleep(nanoseconds: UInt64(attempt * 1_000_000_000))
          }
      }
  }
  ```

### Race Conditions

- [ ] **Add Cache Queue** (LikesVM.swift, ActivePattern.swift)
  ```swift
  private let cacheQueue = DispatchQueue(label: "com.vestivia.cache", qos: .utility)
  
  private func saveCache() {
      cacheQueue.async {
          // All cache writes here
      }
  }
  ```

---

## 🔧 CODE QUALITY - Fix Next Sprint

### Extract Constants

- [ ] **Create Constants File**
  ```swift
  enum AppConstants {
      enum Images {
          static let maxBytes = 300 * 1024
          static let thumbnailSize: CGFloat = 100
          static let compressionQuality: CGFloat = 0.8
      }
      
      enum Pagination {
          static let defaultPageSize = 50
          static let maxListingsPerQuery = 100
      }
      
      enum Cache {
          static let maxAge: TimeInterval = 86400 // 1 day
      }
  }
  ```

### Clean Up Debug Code

- [ ] **Remove/Guard Debug Prints**
  ```swift
  #if DEBUG
  private func log(_ message: String) {
      print("[ClassName] \(message)")
  }
  #else
  private func log(_ message: String) { }
  #endif
  ```

### Naming Consistency

- [ ] **Standardize ViewModel Naming**
  - Rename `ProfileVM` → `ProfileViewModel`
  - Rename `LikesVM` → `LikesViewModel`
  - Rename `FollowVM` → `FollowViewModel`

- [ ] **Standardize Fetch Methods**
  - `fetch*` for network calls
  - `load*` for cache/disk
  - `get*` for computed properties

### Extract Large Functions

- [ ] **Split AddListingViewSingle.body** (350+ lines)
  - Extract image section
  - Extract details section
  - Extract price section

- [ ] **Split SellerProfileView** (450+ lines)
  - Extract header view
  - Extract tabs bar
  - Extract listing list

---

## 🔒 SECURITY - Review & Fix

### Input Sanitization

- [ ] **Add XSS Protection**
  ```swift
  func sanitizeInput(_ input: String) -> String {
      input
          .replacingOccurrences(of: "<", with: "")
          .replacingOccurrences(of: ">", with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
  }
  ```

### Remove Sensitive Logs

- [ ] **Audit All Print Statements**
  - Remove file paths from logs
  - Remove user IDs from logs
  - Remove storage paths from logs

### Rate Limiting

- [ ] **Add Upload Throttle** (CloudflareUploader.swift)
  ```swift
  actor UploadThrottle {
      private var lastUpload: Date?
      
      func canUpload() -> Bool {
          guard let last = lastUpload else {
              lastUpload = Date()
              return true
          }
          if Date().timeIntervalSince(last) > 2.0 {
              lastUpload = Date()
              return true
          }
          return false
      }
  }
  ```

---

## 📱 UX IMPROVEMENTS

### Accessibility

- [ ] **Add Labels to Icon Buttons**
  ```swift
  Button { } label: {
      Image(systemName: "chevron.left")
  }
  .accessibilityLabel("Go back")
  .accessibilityHint("Returns to previous screen")
  ```

### Loading Indicators

- [ ] **Add to All Async Operations**
  ```swift
  @State private var isLoading = false
  
  Button("Submit") {
      isLoading = true
      Task {
          await submit()
          isLoading = false
      }
  }
  .disabled(isLoading)
  .overlay {
      if isLoading {
          ProgressView()
      }
  }
  ```

### Empty States

- [ ] **Improve All Empty States**
  ```swift
  struct EmptyStateView: View {
      let title: String
      let message: String
      let systemImage: String
      let action: (() -> Void)?
      
      var body: some View {
          VStack(spacing: 16) {
              Image(systemName: systemImage)
                  .font(.system(size: 48))
                  .foregroundStyle(.secondary)
              Text(title).font(.headline)
              Text(message).font(.subheadline).foregroundStyle(.secondary)
              if let action {
                  Button("Try Again", action: action)
              }
          }
      }
  }
  ```

---

## 🧪 TESTING - Add Tests For

### Unit Tests Needed

- [ ] **ListingViewModel validation**
- [ ] **Price formatting logic**
- [ ] **Cache read/write operations**
- [ ] **Date parsing logic**
- [ ] **Image compression quality**

### Integration Tests Needed

- [ ] **Complete listing submission flow**
- [ ] **Pattern match end-to-end**
- [ ] **Like/unlike operations**
- [ ] **Follow/unfollow**

---

## 📊 MONITORING - Add Tracking

### Analytics Events

- [ ] **Track listing creation**
  ```swift
  Analytics.logEvent("listing_created", parameters: [
      "category": category,
      "price": price,
      "has_pattern": patternJPEGData != nil
  ])
  ```

- [ ] **Track pattern matches**
- [ ] **Track purchases**
- [ ] **Track errors**

### Performance Monitoring

- [ ] **Add Firebase Performance**
  ```swift
  let trace = Performance.startTrace(name: "listing_submission")
  await submitListing()
  trace?.stop()
  ```

---

## 🔄 REFACTORING - Plan For Future

### Architecture

- [ ] **Create Repository Layer**
  ```swift
  protocol ListingRepository {
      func create(_ listing: Listing) async throws
      func fetch(id: String) async throws -> Listing
      func update(_ listing: Listing) async throws
      func delete(id: String) async throws
  }
  ```

- [ ] **Extract Services**
  - ImageUploadService
  - CacheService
  - ValidationService

### Consolidation

- [ ] **Unified Cache Manager**
  ```swift
  actor CacheManager<T: Codable> {
      func save(_ item: T, forKey key: String) async throws
      func load(forKey key: String) async throws -> T?
      func clear(forKey key: String) async throws
  }
  ```

---

## ✅ COMPLETION CHECKLIST

Before marking as complete, verify:

- [ ] All critical issues fixed
- [ ] All high priority issues addressed
- [ ] Code compiles without warnings
- [ ] Manual testing passed
- [ ] Performance acceptable on older devices
- [ ] Memory leaks checked with Instruments
- [ ] Error cases handled gracefully
- [ ] User-facing strings finalized
- [ ] Analytics events firing correctly

---

## 📝 NOTES

- Review CHECKOUT_CODE_REVIEW.md for additional context on performance issues
- Coordinate with backend team on API endpoint configuration
- Consider code review before each PR merge
- Add pre-commit hooks for lint checks

---

**Last Updated:** January 28, 2026  
**Reviewed By:** Claude  
**Next Review:** After critical fixes completed
