// Replace all debugDumpHits calls with lightweight logging

// BEFORE (SLOW):
#if DEBUG
private func debugDumpHits(_ hits: [ListingHit], source: String) {
    print("🔎 [Algolia] \(source) decoded \(hits.count) hits")
    for (idx, h) in hits.enumerated() {
        let m = Mirror(reflecting: h)
        // ... expensive reflection
    }
}
#endif

// AFTER (FAST):
#if DEBUG
private func debugLog(_ message: String) {
    // Only log count, not individual items
    print("[Algolia] \(message)")
}
#endif

// Replace all calls like:
debugDumpHits(typedHits, source: "onResults")

// With:
#if DEBUG
debugLog("onResults: \(typedHits.count) items")
#endif

// REMOVE these entirely (they're called on every view update):
.onChange(of: coordinator.hitsController.hits.compactMap { $0 }.count) { _ in
    debugDumpHits(context: "onChange")  // ⚠️ DELETE THIS
}
