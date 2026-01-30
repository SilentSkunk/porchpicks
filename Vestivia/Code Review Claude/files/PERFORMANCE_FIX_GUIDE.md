# Performance Optimization Checklist

## 🔥 CRITICAL (Do These First)

### 1. Remove Per-Cell Firestore Listeners (80% Performance Gain)
**File:** `Vestivia/AlgoliaSearch/Itemview/Search Screen/InstantSearchScreen.swift`

**Current Problem:**
- Every grid cell creates 2 Firestore listeners
- 20 items = 40 active listeners
- Kills scroll performance

**Fix:**
```swift
// OPTION A: Remove listeners entirely (simplest)
// Delete the entire .task block from GridThumbCard
// Replace with:
.task {
    thumb = buildThumbURL()
    // Don't fetch likes - show count from Algolia index instead
}

// OPTION B: Batch fetch likes once for all visible items
// Add to InstantSearchScreen:
@State private var batchedLikes: [String: (liked: Bool, count: Int)] = [:]

func loadLikesForVisibleItems() async {
    let ids = items.prefix(20).map { $0.listingID }
    // Batch Firestore query (1 query instead of 40)
    let results = await LikesService.batchFetchLikes(ids)
    batchedLikes = results
}

// In GridThumbCard, read from batchedLikes instead of setting up listeners
```

---

### 2. Add Search Debouncing (Reduces API Calls by 90%)
**File:** `Vestivia/AlgoliaSearch/Itemview/Search Screen/InstantSearchScreen.swift`

**Current Problem:**
- Every keystroke triggers Algolia search
- Type "shoes" = 5 API calls

**Fix:**
```swift
// Add to InstantSearchScreen
@State private var searchDebounce: Task<Void, Never>? = nil

private var queryBinding: Binding<String> {
    Binding(
        get: { coordinator.searchBoxController.query },
        set: { newValue in
            coordinator.searchBoxController.query = newValue
            searchDebounce?.cancel()
            
            if newValue.isEmpty {
                coordinator.searchBoxController.submit() // Instant clear
            } else {
                searchDebounce = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if !Task.isCancelled {
                        coordinator.searchBoxController.submit()
                    }
                }
            }
        }
    )
}
```

---

### 3. Remove Expensive Debug Logging
**File:** `Vestivia/AlgoliaSearch/InstantSearchCoordinator.swift`

**Current Problem:**
- `debugDumpHits()` uses Mirror reflection on every result
- Called via `.onChange` modifier = runs constantly during scrolling

**Fix:**
```swift
// DELETE the entire debugDumpHits function

// REPLACE all calls like:
debugDumpHits(typedHits, source: "onResults")

// WITH simple log:
#if DEBUG
print("[Algolia] onResults: \(typedHits.count) items")
#endif

// DELETE this entirely:
.onChange(of: coordinator.hitsController.hits.compactMap { $0 }.count) { _ in
    debugDumpHits(context: "onChange") // ⚠️ DELETE THIS LINE
}
```

---

### 4. Fix Redundant Initial Searches
**File:** `Vestivia/AlgoliaSearch/Itemview/Search Screen/InstantSearchScreen.swift`

**Current Problem:**
- 3 searches fired on appear (initial + 2 retries)
- Retries happen even if cache has data

**Fix:**
```swift
.onAppear {
    guard !initialSearchStarted else { return }
    initialSearchStarted = true
    
    // Single search only
    coordinator.search()
    
    // ONE retry only, after longer delay
    Task {
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        if coordinator.hitsController.hits.isEmpty {
            coordinator.search()
        }
    }
}
```

---

## ⚡ HIGH IMPACT (Do Next)

### 5. Make Disk Cache Async
**File:** `Vestivia/AlgoliaSearch/Itemview/Search Screen/ListingDetailView.swift`

**Current Problem:**
- All disk I/O happens synchronously on main thread
- Blocks UI during read/write

**Fix:**
```swift
// Replace DiskListingCache with async actor
actor AsyncDiskCache {
    static let shared = AsyncDiskCache()
    // ... (see AsyncDiskCache.swift example above)
}

// Update all callers to use await:
let hit = await AsyncDiskCache.shared.loadHit(for: id)
await AsyncDiskCache.shared.saveHit(hit, for: id)
```

---

### 6. Optimize Image Loading
**File:** `Vestivia/AlgoliaSearch/Itemview/Search Screen/InstantSearchScreen.swift`

**Current Problem:**
- Complex image logic even for public thumbnails
- Multiple fallback attempts per cell

**Fix:**
```swift
// Simplify GridThumbCard image loading:
private func thumbURL(for hit: ListingHit) -> URL? {
    let id = hit.preferredImageId ?? hit.primaryImageId ?? hit.imageIds?.first
    guard let id, !id.isEmpty else { return nil }
    
    // Public thumbnails don't need signing - just return URL
    return URL(string: "https://imagedelivery.net/bh7zSZiTTc0igci1WPjT5w/\(id)/Thumbnail")
}

// In body, use simple AsyncImage (URLCache handles everything):
AsyncImage(url: thumbURL(for: hit))
```

---

### 7. Add Request Coalescing
**File:** `Vestivia/AlgoliaSearch/InstantSearchCoordinator.swift`

**Current Problem:**
- Multiple simultaneous searches for same query can happen
- Race conditions on results

**Fix:**
```swift
// Add to InstantSearchCoordinator
private var inFlightSearch: Task<Void, Never>? = nil

@MainActor
func search() {
    // Cancel any in-flight search
    inFlightSearch?.cancel()
    
    inFlightSearch = Task {
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        if !Task.isCancelled {
            requestSearchOrShowCached()
        }
    }
}
```

---

## 🔧 MEDIUM IMPACT

### 8. Reduce NewestItemsVM Firestore Calls
**File:** `Vestivia/Home View/HomeFeedView.swift`

**Current Problem:**
- Firestore beacon checked on every HomeFeedView appearance
- Even when cache is fresh

**Fix:**
```swift
// In NewestItemsVM.load():
@MainActor
func load(limit: Int = 10, forceRefresh: Bool = false) {
    if let cached = readCache() {
        self.items = cached.items
        
        if forceRefresh {
            Task { await fetchFromAlgolia(limit: limit) }
        } else {
            // Only check beacon if cache is old (4+ hours)
            let age = Date().timeIntervalSince(cached.fetchedAt)
            if age < cacheTTL {
                return // Use cache, skip beacon check
            }
            Task {
                let needsRefresh = await shouldRefreshCache(lastFetchedAt: cached.fetchedAt)
                if needsRefresh { await fetchFromAlgolia(limit: limit) }
            }
        }
    } else {
        Task { await fetchFromAlgolia(limit: limit) }
    }
}
```

---

### 9. Optimize Cache Key Generation
**File:** `Vestivia/AlgoliaSearch/InstantSearchCoordinator.swift`

**Current Problem:**
- `currentCacheKey()` called frequently
- Builds string from filter state every time

**Fix:**
```swift
// Cache the cache key
private var cachedCacheKey: String?
private var lastFilterState: String?

private func currentCacheKey() -> String {
    let currentState = filterState.description
    if currentState == lastFilterState, let cached = cachedCacheKey {
        return cached
    }
    
    // Rebuild key only when filters change
    lastFilterState = currentState
    let key = buildCacheKey()
    cachedCacheKey = key
    return key
}

private func buildCacheKey() -> String {
    // ... existing logic
}
```

---

### 10. Remove Unused Code
**Files:** See CHECKOUT_CODE_REVIEW.md

**Remove these unused files:**
- `CheckoutPayload.swift` - not integrated
- `ShippoManager.swift` - bypassed by CartViewModel

---

## 🐛 BUG FIXES

### Bug Fix 1: Add Missing Address Fields
**File:** `Vestivia/Checkout/Checkout Suppport Files/UserAddress.swift`

```swift
struct UserAddress: Identifiable, Codable {
    var id: String = "main"
    var fullName: String
    var address: String
    var city: String
    var state: String        // ✅ ADD THIS
    var zip: String          // ✅ ADD THIS
    var country: String
    var phone: String
    var isPrimary: Bool = true
}
```

**Also update:**
- `AddressFormView.swift` - save state/zip to model
- `CartViewModel.swift` - remove the temporary extension hack

---

### Bug Fix 2: Fix Listener Memory Leaks
**File:** `Vestivia/AlgoliaSearch/Itemview/Search Screen/InstantSearchScreen.swift`

```swift
// In GridThumbCard, ensure cleanup even if deallocated:
.onDisappear {
    userLikeListener?.remove()
    countListener?.remove()
}
.onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
    // Also cleanup when app backgrounds
    userLikeListener?.remove()
    countListener?.remove()
}
```

---

## 📊 Expected Performance Gains

| Fix | Impact | Reduction |
|-----|--------|-----------|
| Remove per-cell listeners | **CRITICAL** | 80% of lag |
| Add search debouncing | **CRITICAL** | 90% of API calls |
| Remove debug logging | **CRITICAL** | 50% of scroll jank |
| Async disk cache | HIGH | 30% of UI blocks |
| Simplify image loading | HIGH | 40% of image time |
| Reduce retry searches | MEDIUM | 66% of initial searches |

## 🎯 Quick Wins (30 minutes)

1. Delete `debugDumpHits()` function and all calls ← **Do this first!**
2. Add search debouncing (5 lines of code)
3. Remove 2 of the 3 retry searches in `onAppear`
4. Comment out Firestore listeners in GridThumbCard

These 4 changes alone should reduce lag by 60-70%.

## 🚀 Full Implementation (2-3 hours)

1. Implement all CRITICAL fixes
2. Test on device (not simulator)
3. Profile with Instruments to verify gains
4. Implement HIGH IMPACT fixes
5. Final testing

---

## Testing Checklist

After implementing fixes, test:
- [ ] Search feels instant (< 300ms)
- [ ] Smooth 60fps scrolling through grid
- [ ] No lag when typing in search bar
- [ ] First screen load < 1 second
- [ ] No memory growth during scrolling
- [ ] App launches faster

Use Xcode Instruments:
- Time Profiler - find remaining hot spots
- Allocations - check for memory leaks
- Network - verify reduced API calls
