//
//  MatchHit.swift
//  Exchange
//
//  Created by William Hunsucker on 9/18/25.
//


import SwiftUI
import Combine
import Firebase
import FirebaseFirestore
import UserNotifications

// MARK: - Model

struct MatchHit: Identifiable, Equatable {
    let id: String            // listingId (doc ID)
    let listingId: String
    let sellerUid: String?
    let searchId: String?
    let brandLower: String
    let score: Double?
    let listingRef: String?
    let createdAt: Date?
    var seen: Bool
    
    init(id: String,
         listingId: String,
         sellerUid: String?,
         searchId: String?,
         brandLower: String,
         score: Double?,
         listingRef: String?,
         createdAt: Date?,
         seen: Bool)
    {
        self.id = id
        self.listingId = listingId
        self.sellerUid = sellerUid
        self.searchId = searchId
        self.brandLower = brandLower
        self.score = score
        self.listingRef = listingRef
        self.createdAt = createdAt
        self.seen = seen
    }
    
    init?(doc: DocumentSnapshot) {
        let data = doc.data() ?? [:]
        self.id = doc.documentID
        self.listingId = data["listingId"] as? String ?? doc.documentID
        self.sellerUid = data["sellerUid"] as? String
        self.searchId = data["searchId"] as? String
        self.brandLower = data["brandLower"] as? String ?? ""
        self.score = data["score"] as? Double
        self.listingRef = data["listingRef"] as? String
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        self.seen = data["seen"] as? Bool ?? false
    }
}

// MARK: - In-app notifier

final class InAppNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = InAppNotifier()
    private override init() { super.init() }

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }
    
    func notifyNewMatch(_ hit: MatchHit) {
        let content = UNMutableNotificationContent()
        let brand = hit.brandLower.capitalized
        content.title = "New match found"
        content.body = "We found a match for \(brand). Tap to view."
        content.sound = .default
        content.userInfo = ["listingId": hit.listingId]
        
        let request = UNNotificationRequest(
            identifier: "match_\(hit.id)",
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    // Foreground presentation (banner + sound while app is open)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

// MARK: - Service

@MainActor
final class MatchInboxService: ObservableObject {
    @Published private(set) var matches: [MatchHit] = []
    @Published private(set) var isLoading = false
    
    private let uid: String
    private var listener: ListenerRegistration?
    private var notifiedIds = Set<String>() // stop duplicate local notifs
    
    init(uid: String) {
        self.uid = uid
        InAppNotifier.shared.configure()
        start()
    }
    
    deinit {
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }
    
    func start() {
        guard listener == nil else { return }
        isLoading = true
        
        let db = Firestore.firestore()
        let ref = db.collection("users").document(uid).collection("matchInbox")
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
        
        listener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            self.isLoading = false
            
            if let error = error {
                print("[MatchInbox] listen error:", error)
                return
            }
            
            guard let docs = snapshot?.documents else {
                self.matches = []
                return
            }
            
            let old = self.matches
            let previousIds = Set(old.map { $0.id })
            
            var items: [MatchHit] = []
            items.reserveCapacity(docs.count)
            for d in docs {
                if let hit = MatchHit(doc: d) {
                    items.append(hit)
                }
            }
            self.matches = items
            
            // Fire notifications for brand new unseen hits
            for hit in items where !hit.seen && !previousIds.contains(hit.id) && !self.notifiedIds.contains(hit.id) {
                self.notifiedIds.insert(hit.id)
                InAppNotifier.shared.notifyNewMatch(hit)
            }
        }
    }
    
    func stop() {
        listener?.remove()
        listener = nil
    }
    
    func markSeen(_ hit: MatchHit) {
        let db = Firestore.firestore()
        let doc = db.collection("users").document(uid).collection("matchInbox").document(hit.id)
        doc.setData(["seen": true], merge: true)
        
        if let idx = matches.firstIndex(where: { $0.id == hit.id }) {
            var updated = matches
            updated[idx].seen = true
            matches = updated
        }
    }
    
    func clearAllSeen() {
        let db = Firestore.firestore()
        let batch = db.batch()
        for hit in matches where hit.seen {
            let ref = db.collection("users").document(uid).collection("matchInbox").document(hit.id)
            batch.setData(["seen": true], forDocument: ref, merge: true)
        }
        batch.commit(completion: nil)
    }
}

// MARK: - View

struct MatchesView: View {
    @StateObject private var svc: MatchInboxService
    private let onOpenListing: ((MatchHit) -> Void)?
    
    init(uid: String, onOpenListing: ((MatchHit) -> Void)? = nil) {
        _svc = StateObject(wrappedValue: MatchInboxService(uid: uid))
        self.onOpenListing = onOpenListing
    }
    
    var body: some View {
        Group {
            if svc.isLoading && svc.matches.isEmpty {
                ProgressView("Loading matches…")
            } else if svc.matches.isEmpty {
                ContentUnavailableView("No matches yet", systemImage: "magnifyingglass.circle")
            } else {
                List {
                    ForEach(svc.matches) { hit in
                        Button {
                            svc.markSeen(hit)
                            onOpenListing?(hit)
                        } label: {
                            HStack(spacing: 12) {
                                // Placeholder avatar based on brand
                                ZStack {
                                    Circle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 44, height: 44)
                                    Text(hit.brandLower.prefix(1).uppercased())
                                        .font(.headline)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(hit.brandLower.capitalized)
                                            .font(.headline)
                                        if let score = hit.score {
                                            Text(String(format: "• %.0f%%", score * 100))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text("Listing \(hit.listingId)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    
                                    if let created = hit.createdAt {
                                        Text(created.relativeDescription())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if !hit.seen {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 10, height: 10)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Matches")
        .onAppear {
            // Ensure notifications can display while foregrounded
            InAppNotifier.shared.configure()
        }
    }
}

// MARK: - Date helper

private extension Date {
    func relativeDescription(reference: Date = .init()) -> String {
        let seconds = Int(reference.timeIntervalSince(self))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}

// MARK: - Quick preview (requires Firebase configured in previews if you actually run it)

#if DEBUG
struct MatchesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MatchesView(uid: "preview-user") { _ in }
        }
    }
}
#endif
