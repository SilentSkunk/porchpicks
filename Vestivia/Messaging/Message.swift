//
//  Message.swift
//  Exchange
//
//  Created by William Hunsucker on 8/21/25.
//

//
//  MessagingModule.swift
///Volumes/Project Files/App Projects/Exchange/Vestivia/Messaging/Message.swift
//  Requires: FirebaseAuth, FirebaseFirestore, FirebaseFirestoreSwift
//  NOTE: Firebase is configured centrally in AppDelegate (via FirebaseApp.configure()).
//  Do not call FirebaseApp.configure() here.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Network

// MARK: - Models

struct Message: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var text: String
    var senderId: String
    @ServerTimestamp var createdAt: Timestamp?
    var attachments: [String]? // optional future use

    enum CodingKeys: String, CodingKey { case id, text, senderId, createdAt, attachments }

    var date: Date { createdAt?.dateValue() ?? .distantPast }
    var isFromCurrentUser: Bool { Auth.auth().currentUser?.uid == senderId }
}

struct Conversation: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var members: [String]
    var lastMessage: String?
    var lastSenderId: String?
    @ServerTimestamp var updatedAt: Timestamp?
    var title: String? // Optional label for UI (e.g., other user’s name)

    enum CodingKeys: String, CodingKey { case id, members, lastMessage, lastSenderId, updatedAt, title }
}

// MARK: - Network Reachability
final class NetMon: ObservableObject {
    static let shared = NetMon()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "netmon")
    @Published var isReachable: Bool = true
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isReachable = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }
}

// MARK: - Firestore Service

final class ChatService {
    static let shared = ChatService()
    private init() {}
    private lazy var db = Firestore.firestore()

    private var conversations: CollectionReference { db.collection("conversations") }
    private func messages(cid: String) -> CollectionReference {
        conversations.document(cid).collection("messages")
    }

    // Create (or reuse) a 1:1 conversation by members (sorted)
    func getOrCreateConversation(between uids: [String]) async throws -> String {
        let sorted = uids.sorted()
        // Try to find existing conversation with exact members
        let q = conversations
            .whereField("members", arrayContains: sorted.first!)
            .order(by: "updatedAt", descending: true)

        let snap = try await q.getDocuments()
        if let doc = snap.documents.first(where: { (try? $0.data(as: Conversation.self))?.members.sorted() == sorted }) {
            return doc.documentID
        }

        // Create new
        let ref = conversations.document()
        try await ref.setData([
            "members": sorted,
            "updatedAt": FieldValue.serverTimestamp()
        ])
        return ref.documentID
    }

    // Simple creation if you already decided to always make new threads
    func createConversation(members: [String]) async throws -> String {
        let ref = conversations.document()
        try await ref.setData([
            "members": members.sorted(),
            "updatedAt": FieldValue.serverTimestamp()
        ])
        return ref.documentID
    }

    func sendMessage(cid: String, text: String, from uid: String) async throws {
        let convRef = conversations.document(cid)
        let msgRef  = convRef.collection("messages").document()
        let now = FieldValue.serverTimestamp()

        let batch = db.batch()
        batch.setData([
            "text": text,
            "senderId": uid,
            "createdAt": now
        ], forDocument: msgRef)

        batch.updateData([
            "lastMessage": text,
            "lastSenderId": uid,
            "updatedAt": now
        ], forDocument: convRef)

        try await batch.commit()
    }

    // Inbox for current user
    func listenConversations(for uid: String, onChange: @escaping ([Conversation]) -> Void) -> ListenerRegistration {
        conversations
            .whereField("members", arrayContains: uid)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { snap, err in
                if let err = err {
                    print("[Conversations] listener error:", err.localizedDescription)
                    onChange([])
                    return
                }
                guard let snap = snap else {
                    print("[Conversations] listener: snapshot is nil")
                    onChange([])
                    return
                }
                let convs: [Conversation] = snap.documents.compactMap { try? $0.data(as: Conversation.self) }
                onChange(convs)
            }
    }

    // Live messages for a thread
    func listenMessages(cid: String, limit: Int = 50, onChange: @escaping ([Message]) -> Void) -> ListenerRegistration {
        messages(cid: cid)
            .order(by: "createdAt", descending: false)
            .limit(to: limit)
            .addSnapshotListener { snap, err in
                if let err = err {
                    print("[Messages] listener error (cid=\(cid)):", err.localizedDescription)
                    onChange([])
                    return
                }
                guard let snap = snap else {
                    print("[Messages] listener: snapshot is nil (cid=\(cid))")
                    onChange([])
                    return
                }
                let msgs: [Message] = snap.documents.compactMap { try? $0.data(as: Message.self) }
                onChange(msgs)
            }
    }

    // Pagination example (older page)
    func loadOlderMessages(cid: String, after last: DocumentSnapshot, limit: Int = 50) async throws -> [Message] {
        let snap = try await messages(cid: cid)
            .order(by: "createdAt", descending: false)
            .start(afterDocument: last)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Message.self) }
    }
}

// MARK: - ViewModels

@MainActor
final class ConversationsVM: ObservableObject {
    @Published var conversations: [Conversation] = []
    private var listener: ListenerRegistration?

    func start(uid: String) {
        print("[ConversationsVM] start listening for uid=\(uid)")
        stop()
        listener = ChatService.shared.listenConversations(for: uid) { [weak self] convs in
            DispatchQueue.main.async { self?.conversations = convs }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }
}

@MainActor
final class ChatVM: ObservableObject {
    @Published var messages: [Message] = []
    @Published var input: String = ""

    let cid: String
    private var listener: ListenerRegistration?

    init(cid: String) { self.cid = cid }

    func start() {
        stop()
        listener = ChatService.shared.listenMessages(cid: cid) { [weak self] msgs in
            DispatchQueue.main.async { self?.messages = msgs }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    func send() async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
        input = ""
        do {
            try await ChatService.shared.sendMessage(cid: cid, text: trimmed, from: uid)
        } catch {
            // restore input if failed
            input = trimmed
            print("send failed:", error.localizedDescription)
        }
    }
}

// MARK: - Views

struct ChatBubble: View {
    let message: Message

    var body: some View {
        HStack(spacing: 8) {
            if message.isFromCurrentUser { Spacer(minLength: 24) }
            Text(message.text)
                .padding(10)
                .background(message.isFromCurrentUser ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(message.isFromCurrentUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !message.isFromCurrentUser { Spacer(minLength: 24) }
        }
        .padding(.horizontal)
    }
}

struct ChatView: View {
    @StateObject var vm: ChatVM
    @StateObject private var net = NetMon.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.messages) { msg in
                            ChatBubble(message: msg)
                                .id(msg.id ?? UUID().uuidString)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            if !net.isReachable {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                    Text("Offline — messages won’t send")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Message", text: $vm.input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button("Send") {
                    Task { await vm.send() }
                }
                .disabled(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !net.isReachable)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task { if net.isReachable { vm.start() } else { print("[Chat] offline, not starting") } }
        .onChange(of: net.isReachable) { _, reachable in
            if reachable {
                print("[Chat] came online → start listener")
                vm.start()
            } else {
                print("[Chat] went offline → stop listener")
                vm.stop()
            }
        }
        .onDisappear { vm.stop() }
    }
}

struct ConversationsListView: View {
    @StateObject var vm = ConversationsVM()
    @StateObject private var net = NetMon.shared

    var body: some View {
        VStack(spacing: 0) {
            if !net.isReachable {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                    Text("Offline — reconnecting…")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.vertical, 6)
            }

            List(vm.conversations) { c in
                NavigationLink(value: c) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title ?? "Conversation")
                            .font(.headline)
                        if let last = c.lastMessage {
                            Text(last).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle("Messages")
        .task {
            if let uid = Auth.auth().currentUser?.uid, net.isReachable {
                vm.start(uid: uid)
            } else {
                print("[Conversations] not starting, offline or no uid")
            }
        }
        .onChange(of: net.isReachable) { _, reachable in
            if reachable, let uid = Auth.auth().currentUser?.uid {
                print("[Conversations] came online → start listener")
                vm.start(uid: uid)
            } else {
                print("[Conversations] went offline → stop listener")
                vm.stop()
            }
        }
        .onDisappear { vm.stop() }
        .navigationDestination(for: Conversation.self) { conv in
            if let cid = conv.id {
                ChatView(vm: ChatVM(cid: cid))
            } else {
                Text("Missing conversation id")
            }
        }
    }
}
