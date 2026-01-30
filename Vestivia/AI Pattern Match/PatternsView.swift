//
//  PatternsView.swift
//  Exchange
//
//  Created by William Hunsucker on 9/9/25.
//



import SwiftUI
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore
import FirebaseCore

struct StorageThumb: View {
    let path: String
    let size: CGFloat

    @State private var url: URL?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.secondarySystemBackground))
                            ProgressView()
                        }
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.tertiarySystemBackground))
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                    @unknown default:
                        Color.clear
                    }
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.secondarySystemBackground))
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: path) {
            guard !isLoading else { return }
            isLoading = true
            do {
                let ref = Storage.storage().reference(withPath: path)
                let signed = try await ref.downloadURL()
                self.url = signed
            } catch {
                print("[PatternsView] thumb URL error for \(path): \(error.localizedDescription)")
            }
            isLoading = false
        }
    }
}

struct PatternsView: View {
    @StateObject private var vm = PatternsListVM()

    var body: some View {
        List {
            // HERO SECTION
            Section {
                NavigationLink {
                    PatternMatchView()
                } label: {
                    PatternsHeroCard()
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .listSectionSpacing(8)
            .listRowBackground(Color.clear)

            // ACTIVE PATTERNS SECTION
            Section(header:
                Text("Current Active Patterns")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            ) {
                if vm.isLoading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading…")
                            .foregroundStyle(.secondary)
                    }
                } else if vm.items.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.slash").foregroundStyle(.secondary)
                        Text("No active patterns being searched")
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .rounded))
                        Spacer()
                    }
                } else {
                    ForEach(vm.items) { item in
                        HStack(spacing: 16) {
                            if let url = item.thumbnailURL {
                                RowAsyncThumb(url: url)
                            } else {
                                StorageThumb(path: item.path, size: 44)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.brandDisplay)
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(.primary)
                                Text("#\(item.id.prefix(8))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await vm.delete(item) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                if let err = vm.error, !err.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            Text(err).font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                        }
                        Button("Retry") {
                            vm.refresh()
                        }
                        .buttonStyle(.bordered)
                        .font(.footnote)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Patterns")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.load() }
        .refreshable { vm.refresh() }
    }
}

// MARK: - Components

private struct PatternsHeroCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.systemGray6))
            .overlay(
                PatternsHeroPlaceholder()
                    .padding(28)
            )
            .frame(height: 140)
    }
}

private struct PatternsHeroPlaceholder: View {
    var body: some View {
        ZStack {
            // Soft “empty state” shapes
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemGray5))
            HStack(spacing: 20) {
                RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray4)).frame(width: 56, height: 56)
                Circle().fill(Color(.systemGray4)).frame(width: 36, height: 36)
                RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray4)).frame(width: 48, height: 48)
            }
            .opacity(0.6)
        }
    }
}

private struct RowAsyncThumb: View {
    let url: URL
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(width: 44, height: 44)
            case .success(let img):
                img.resizable().scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            case .failure:
                Image(systemName: "photo")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6))
                    )
            @unknown default:
                Color.clear.frame(width: 44, height: 44)
            }
        }
    }
}

private struct IconTile: View {
    let symbols: [String]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.blue.opacity(0.10))
                .frame(width: 44, height: 44)
            // 3 small glyphs inside tile
            HStack(spacing: 4) {
                Image(systemName: symbols.first ?? "triangle.fill")
                Image(systemName: symbols.dropFirst().first ?? "gearshape.fill")
                Image(systemName: symbols.dropFirst(2).first ?? "square.fill")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.blue.opacity(0.9))
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Active Patterns (Storage-backed)

struct PatternEntry: Identifiable, Hashable, Codable {
    let id: String          // searchId (filename without extension)
    let brand: String       // brandLower (folder name)
    let path: String        // users_active_patterns/<uid>/<brand>/<id>.jpg
    var thumbnailURL: URL? = nil  // download URL for preview (not persisted)

    var brandDisplay: String {
        brand.replacingOccurrences(of: "-", with: " ").capitalized
    }

    enum CodingKeys: String, CodingKey { case id, brand, path }
}

// MARK: - Local Cache
fileprivate enum LocalActivePatternsStore {
    static func cacheKey(for uid: String) -> String { "active_patterns_\(uid)" }
    static func hydratedKey(for uid: String) -> String { "active_patterns_hydrated_\(uid)" }

    static func load(uid: String) -> [PatternEntry] {
        let key = cacheKey(for: uid)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        do { return try JSONDecoder().decode([PatternEntry].self, from: data) } catch { return [] }
    }

    static func save(uid: String, items: [PatternEntry]) {
        let key = cacheKey(for: uid)
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func markHydrated(uid: String) { UserDefaults.standard.set(true, forKey: hydratedKey(for: uid)) }
    static func isHydrated(uid: String) -> Bool { UserDefaults.standard.bool(forKey: hydratedKey(for: uid)) }

    static func upsert(uid: String, entry: PatternEntry) {
        var current = load(uid: uid)
        if let idx = current.firstIndex(where: { $0.id == entry.id && $0.brand == entry.brand }) {
            current[idx] = entry
        } else {
            current.insert(entry, at: 0)
        }
        save(uid: uid, items: current)
    }
}

@MainActor
final class PatternsListVM: ObservableObject {
    @Published var items: [PatternEntry] = []
    @Published var isLoading = false
    @Published var error: String?

    /// Toggle to print verbose Storage diagnostics to the Xcode console
    private let debugStorageListing = false

    func load(forceRemote: Bool = false) {
        Task { @MainActor in
            guard let uid = Auth.auth().currentUser?.uid else {
                self.items = []
                self.error = "Not signed in."
                return
            }
            self.error = nil

            // 1) Always show cache immediately
            let cached = LocalActivePatternsStore.load(uid: uid)
            self.items = cached

            // 2) Decide whether to hit remote
            let needsHydrate = !LocalActivePatternsStore.isHydrated(uid: uid)
            let cacheIsEmpty = cached.isEmpty
            if debugStorageListing {
                print("[PatternsListVM] load(): cached=\(cached.count) needsHydrate=\(needsHydrate) forceRemote=\(forceRemote) cacheIsEmpty=\(cacheIsEmpty)")
            }
            if forceRemote || needsHydrate || cacheIsEmpty {
                if debugStorageListing { print("[PatternsListVM] load(): will fetch remote…") }
                await fetchAndStore(uid: uid)
                return
            } else {
                if debugStorageListing { print("[PatternsListVM] load(): using cache only (no remote fetch)") }
            }
        }
    }

    func refresh() { load(forceRemote: true) }

    private func fetchAndStore(uid: String) async {
        self.isLoading = true
        if debugStorageListing { print("[PatternsListVM] fetchAndStore(): begin") }
        do {
            let fresh = try await fetchRemote(uid: uid)
            self.items = fresh
            LocalActivePatternsStore.save(uid: uid, items: fresh)
            LocalActivePatternsStore.markHydrated(uid: uid)
            self.isLoading = false
            if debugStorageListing { print("[PatternsListVM] fetchAndStore(): done items=\(fresh.count)") }
        } catch {
            let msg = error.localizedDescription
            self.error = msg
            self.isLoading = false
            print("[PatternsListVM] fetchAndStore(): ERROR => \(msg)")
        }
    }

    private func fetchRemote(uid: String) async throws -> [PatternEntry] {
        var collected: [PatternEntry] = []
        let rootPath = "users_active_patterns/\(uid)"
        let root = Storage.storage().reference(withPath: rootPath)
        if debugStorageListing {
            print("[PatternsListVM] calling root.listAll() at path=\(rootPath)")
        }

        let top: StorageListResult = try await root.listAll()
        if debugStorageListing {
            print("[PatternsListVM] root.listAll() returned prefixes=\(top.prefixes.count) items=\(top.items.count)")
        }
        let brandFolders = top.prefixes
        if debugStorageListing {
            let brandNames = brandFolders.map { $0.name }
            print("[PatternsListVM] found brand folders: \(brandFolders.count) => \(brandNames)")
            if !top.items.isEmpty {
                print("[PatternsListVM] WARNING: ROOT has unexpected items count=\(top.items.count)")
            }
        }
        if brandFolders.isEmpty {
            if debugStorageListing { print("[PatternsListVM] Fallback to Firestore active_searches — no brand folders found in Storage") }
            let fs = Firestore.firestore()
            let snap = try await fs.collection("active_searches").document(uid).collection("items").limit(to: 100).getDocuments()
            for doc in snap.documents {
                let data = doc.data()
                guard let pathUser = data["storagePathUser"] as? String else { continue }
                // Expect users_active_patterns/<uid>/<brand>/<id>.<ext>
                let comps = pathUser.split(separator: "/").map(String.init)
                if comps.count >= 4 {
                    let brand = comps[2]
                    let file = comps[3]
                    var id = file
                    for ext in [".jpg", ".jpeg", ".png", ".webp"] {
                        if id.lowercased().hasSuffix(ext) { id = String(id.dropLast(ext.count)) }
                    }
                    let fileRef = Storage.storage().reference(withPath: pathUser)
                    let url = try? await fileRef.downloadURL()
                    collected.append(PatternEntry(id: id, brand: brand, path: pathUser, thumbnailURL: url))
                }
            }
            collected.sort { a, b in
                if a.brand == b.brand { return a.id > b.id }
                return a.brand < b.brand
            }
            if debugStorageListing { print("[PatternsListVM] Firestore fallback collected=\(collected.count)") }
            return collected
        }
        for brandRef in brandFolders {
            let brandPath = brandRef.fullPath
            let brand = brandRef.name
            if debugStorageListing { print("[PatternsListVM] brandFolder=\(brandPath)") }

            let brandResult: StorageListResult = try await brandRef.listAll()
            if debugStorageListing { print("[PatternsListVM] brand=\(brand) items=\(brandResult.items.count) prefixes=\(brandResult.prefixes.count)") }

            // Helper to collect files from a given list result
            func collectFiles(_ fileRefs: [StorageReference], brand: String, basePath: String) async -> [PatternEntry] {
                var results: [PatternEntry] = []
                for fileRef in fileRefs {
                    let file = fileRef.name // e.g. 123.jpg / 123.jpeg / 123.png / 123.webp
                    var id = file
                    for ext in [".jpg", ".jpeg", ".png", ".webp"] {
                        if id.lowercased().hasSuffix(ext) { id = String(id.dropLast(ext.count)) }
                    }
                    let path = "\(basePath)/\(file)" // users_active_patterns/<uid>/<brand>/[<searchId>/]<file>

                    var url: URL? = nil
                    do {
                        url = try await fileRef.downloadURL()
                    } catch {
                        if debugStorageListing { print("[PatternsListVM] downloadURL FAILED path=\(path) err=\(error.localizedDescription)") }
                    }

                    if debugStorageListing {
                        do {
                            let meta = try await fileRef.getMetadata()
                            print("[PatternsListVM] file=\(file) size=\(meta.size) type=\(meta.contentType ?? "-") updated=\(meta.updated?.description ?? "-")")
                        } catch {
                            print("[PatternsListVM] metadata FAILED path=\(path) err=\(error.localizedDescription)")
                        }
                    }

                    results.append(PatternEntry(id: id, brand: brand, path: path, thumbnailURL: url))
                }
                return results
            }

            // Collect flat files directly under the brand folder
            collected.append(contentsOf: await collectFiles(brandResult.items, brand: brand, basePath: brandPath))

            // Also descend exactly one level (subfolders like <searchId>/)
            for subRef in brandResult.prefixes {
                let subPath = subRef.fullPath // users_active_patterns/<uid>/<brand>/<searchId>
                do {
                    let sub = try await subRef.listAll()
                    if debugStorageListing { print("[PatternsListVM] subFolder=\(subPath) items=\(sub.items.count) prefixes=\(sub.prefixes.count)") }
                    collected.append(contentsOf: await collectFiles(sub.items, brand: brand, basePath: subPath))
                } catch {
                    if debugStorageListing { print("[PatternsListVM] listAll FAILED for subFolder=\(subPath) err=\(error.localizedDescription)") }
                }
            }
        }
        // Sort by brand then id string (UUID)
        collected.sort { a, b in
            if a.brand == b.brand { return a.id > b.id }
            return a.brand < b.brand
        }
        if debugStorageListing { print("[PatternsListVM] total collected=\(collected.count)") }
        return collected
    }
    // MARK: - Deletion
    /// Convenience single-item delete
    func delete(_ entry: PatternEntry) async { await delete([entry]) }

    /// Delete one or more entries (thumbnail objects) from Firebase Storage and local cache
    func delete(_ entries: [PatternEntry]) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if debugStorageListing { print("[PatternsListVM] delete(): count=\(entries.count)") }

        for entry in entries {
            do {
                let ref = Storage.storage().reference(withPath: entry.path)
                try await ref.delete()
                if debugStorageListing { print("[PatternsListVM] deleted path=\(entry.path)") }
            } catch {
                if debugStorageListing { print("[PatternsListVM] delete FAILED path=\(entry.path) err=\(error.localizedDescription)") }
            }
        }

        await MainActor.run {
            self.items.removeAll { e in entries.contains(where: { $0.id == e.id && $0.brand == e.brand }) }
            LocalActivePatternsStore.save(uid: uid, items: self.items)
        }
    }
}

// MARK: - Preview

struct PatternsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { PatternsView() }
            .environment(\.colorScheme, .light)
    }
}
