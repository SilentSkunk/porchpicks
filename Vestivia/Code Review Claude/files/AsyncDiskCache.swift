// Replace DiskListingCache with async version

actor AsyncDiskListingCache {
    static let shared = AsyncDiskListingCache()
    
    private var baseDir: URL = {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("ListingDetailCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    // All operations are now async and off main thread
    func saveHeroImage(_ data: Data, for id: String) async throws {
        let url = baseDir.appendingPathComponent("heroimg_\(id).jpg")
        try data.write(to: url, options: .atomic)
    }
    
    func loadHeroImage(for id: String) async -> UIImage? {
        let url = baseDir.appendingPathComponent("heroimg_\(id).jpg")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    
    func saveHit(_ hit: ListingHit, for id: String) async throws {
        let url = baseDir.appendingPathComponent("hit_\(id).json")
        let data = try JSONEncoder().encode(hit)
        try data.write(to: url, options: .atomic)
    }
    
    func loadHit(for id: String) async -> ListingHit? {
        let url = baseDir.appendingPathComponent("hit_\(id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ListingHit.self, from: data)
    }
}

// Usage example in ListingDetailHost:
private func loadSignedHero() async {
    isLoading = true
    
    // Check cache first (now async, doesn't block UI)
    if let cached = await AsyncDiskListingCache.shared.loadHeroImage(for: hit.listingID) {
        heroURL = nil // Use cached UIImage instead
        isLoading = false
        return
    }
    
    // ... rest of signing logic
}
