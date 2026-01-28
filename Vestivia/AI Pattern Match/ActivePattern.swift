//
//  ActivePattern.swift
//  Exchange
//
//  Created by William Hunsucker on 9/15/25.
//


import FirebaseAuth
import FirebaseStorage

// Minimal cache model stored in UserDefaults (URL is resolved at render time)
private struct CachedActivePattern: Codable {
    let id: String
    let brand: String
    let storagePath: String
}

fileprivate enum LocalActivePatternsStore {
    private static func cacheKey(for uid: String) -> String { "active_patterns_cache_\(uid)" }
    private static func hydratedKey(for uid: String) -> String { "active_patterns_hydrated_\(uid)" }

    static func load(uid: String) -> [ActivePattern] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: uid)),
              let cached = try? JSONDecoder().decode([CachedActivePattern].self, from: data)
        else { return [] }
        // Map to runtime model; thumbnailURL is fetched on demand in the row UI
        return cached.map { ActivePattern(id: $0.id, brand: $0.brand, storagePath: $0.storagePath, thumbnailURL: nil) }
    }

    static func save(uid: String, items: [ActivePattern]) {
        let toCache = items.map { CachedActivePattern(id: $0.id, brand: $0.brand, storagePath: $0.storagePath) }
        if let data = try? JSONEncoder().encode(toCache) {
            UserDefaults.standard.set(data, forKey: cacheKey(for: uid))
        }
    }

    static func isHydrated(uid: String) -> Bool {
        UserDefaults.standard.bool(forKey: hydratedKey(for: uid))
    }

    static func markHydrated(uid: String) {
        UserDefaults.standard.set(true, forKey: hydratedKey(for: uid))
    }

    static func clear(uid: String) {
        UserDefaults.standard.removeObject(forKey: cacheKey(for: uid))
        UserDefaults.standard.removeObject(forKey: hydratedKey(for: uid))
    }
}

struct ActivePattern: Identifiable, Hashable {
    let id: String           // searchId
    let brand: String        // brandLower
    let storagePath: String  // users_active_patterns/<uid>/<brand>/<id>.jpg
    let thumbnailURL: URL?
}

@MainActor
final class ActivePatternsVM: ObservableObject {
    @Published var items: [ActivePattern] = []
    @Published var isLoading = false
    @Published var error: String?

    /// One-time warm refresh per app session
    private static var didWarmRefreshThisSession = false
    private let debug = true

    func load(forceRemote: Bool = false) {
        guard let uid = Auth.auth().currentUser?.uid else {
            items = []
            error = "Not signed in."
            return
        }

        // Show cache immediately
        let cached = LocalActivePatternsStore.load(uid: uid)
        self.items = cached
        self.error = nil

        // Build a fast lookup of what we already have in cache so we only fetch missing
        let cachedPathSet = Set(cached.map { $0.storagePath })

        // Decide whether to hit remote
        var effectiveForce = forceRemote
        if !Self.didWarmRefreshThisSession {
            // Force exactly once on first app open for this session
            effectiveForce = true
            Self.didWarmRefreshThisSession = true
        }
        let needsHydrate = !LocalActivePatternsStore.isHydrated(uid: uid)
        let cacheIsEmpty = cached.isEmpty
        if debug {
            print("[ActivePatternsVM] load(): cached=\(cached.count) needsHydrate=\(needsHydrate) forceRemote=\(effectiveForce) cacheEmpty=\(cacheIsEmpty)")
        }

        guard effectiveForce || needsHydrate || cacheIsEmpty else { return }

        // Remote fetch
        isLoading = true
        let root = Storage.storage().reference(withPath: "users_active_patterns/\(uid)")
        root.listAll { [weak self] topResult, topErr in
            guard let self = self else { return }
            if let topErr = topErr {
                if self.debug { print("[ActivePatternsVM] root listAll error: \(topErr.localizedDescription)") }
                self.error = topErr.localizedDescription
                self.isLoading = false
                return
            }

            let brands = topResult?.prefixes ?? []
            if self.debug { print("[ActivePatternsVM] root prefixes=\(brands.count) items=\(topResult?.items.count ?? 0)") }

            if brands.isEmpty {
                self.items = []
                LocalActivePatternsStore.save(uid: uid, items: [])
                LocalActivePatternsStore.markHydrated(uid: uid)
                self.isLoading = false
                return
            }

            let group = DispatchGroup()
            var collectedNew: [ActivePattern] = [] // only new items not already in cache

            for brandRef in brands {
                group.enter()
                brandRef.listAll { brandResult, brandErr in
                    if let brandErr = brandErr {
                        if self.debug { print("[ActivePatternsVM] listAll brand error: \(brandErr.localizedDescription)") }
                        group.leave(); return
                    }

                    let brand = brandRef.name
                    let itemRefs = brandResult?.items ?? []
                    if self.debug { print("[ActivePatternsVM] brand=\(brand) items=\(itemRefs.count)") }

                    for fileRef in itemRefs {
                        let fileName = fileRef.name // e.g. <searchId>.jpg
                        let path = "users_active_patterns/\(uid)/\(brand)/\(fileName)"
                        guard !cachedPathSet.contains(path) else { continue }
                        // Remove common image extensions to get the searchId
                        let lower = fileName.lowercased()
                        var searchId = fileName
                        for ext in [".jpg", ".jpeg", ".png", ".webp"] {
                            if lower.hasSuffix(ext) {
                                searchId = String(fileName.dropLast(ext.count))
                                break
                            }
                        }
                        collectedNew.append(ActivePattern(id: searchId, brand: brand, storagePath: path, thumbnailURL: nil))
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                // Merge cache + new items, then sort for display
                var merged = cached
                merged.append(contentsOf: collectedNew)
                let sorted = merged.sorted { a, b in
                    if a.brand == b.brand { return a.id > b.id }
                    return a.brand < b.brand
                }
                self.items = sorted
                LocalActivePatternsStore.save(uid: uid, items: sorted)
                LocalActivePatternsStore.markHydrated(uid: uid)
                self.isLoading = false
                if self.debug { print("[ActivePatternsVM] total collected=\(sorted.count)") }
            }
        }
    }

    func refresh() { load(forceRemote: true) }

    // MARK: - Deletion
    /// Delete a single entry convenience wrapper
    func delete(_ entry: ActivePattern) async {
        await delete([entry])
    }

    /// Delete one or more entries (thumbnail objects) from Firebase Storage and local cache
    func delete(_ entries: [ActivePattern]) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if debug { print("[ActivePatternsVM] delete(): count=\(entries.count)") }

        for entry in entries {
            do {
                let ref = Storage.storage().reference(withPath: entry.storagePath)
                try await ref.delete()
                if debug { print("[ActivePatternsVM] deleted path=\(entry.storagePath)") }
            } catch {
                if debug { print("[ActivePatternsVM] delete FAILED path=\(entry.storagePath) err=\(error.localizedDescription)") }
            }
        }

        await MainActor.run {
            self.items.removeAll { item in
                entries.contains(where: { $0.id == item.id && $0.brand == item.brand })
            }
            LocalActivePatternsStore.save(uid: uid, items: self.items)
        }
    }
}
