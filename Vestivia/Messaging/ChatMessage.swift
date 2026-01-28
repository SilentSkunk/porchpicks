//
//  ChatMessage.swift
//  Exchange
//
//  Created by William Hunsucker on 8/21/25.
//


//
//  ChatScreenUI.swift
//  Pure UI – hook your ChatVM later
//

import SwiftUI

// MARK: - Models used by the UI

struct ChatMessage: Identifiable, Hashable {
    enum Kind: Hashable {
        case text(String)
        case product(Product, note: String)
    }
    struct Product: Hashable {
        var title: String
        var color: String
        var imageURL: String?
    }

    var id = UUID()
    var isMe: Bool
    var sentAt: Date
    var kind: Kind
}

// MARK: - Colors

extension Color {
    static let chatPrimary = Color(red: 82/255, green: 63/255, blue: 236/255) // purple-ish
    static let chatBubbleIn  = Color(.systemGray6)
    static let chatBubbleOut = Color.chatPrimary
}

// MARK: - Bubble shapes

struct Bubble: Shape {
    let isMe: Bool
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        var corners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        // make the “tail corner” sharper (less rounded) for direction
        corners.remove(isMe ? .bottomLeft : .bottomRight)

        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: r, height: r)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Row views

struct ProductCardBubble: View {
    let product: ChatMessage.Product
    let isMe: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Inner white card
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                    if let s = product.imageURL, let url = URL(string: s) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Image(systemName: "bag").resizable().scaledToFit().padding(14)
                            }
                        }
                    } else {
                        Image(systemName: "bag").resizable().scaledToFit().padding(14)
                    }
                }
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(product.title)
                        .font(.subheadline).bold()
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("Color").font(.caption).foregroundStyle(.secondary)
                        Text("·").font(.caption).foregroundStyle(.secondary)
                        Text(product.color).font(.caption)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        }
        .padding(14)
        .background(isMe ? Color.chatBubbleOut : Color.chatBubbleIn)
        .foregroundStyle(isMe ? .white : .primary)
        .clipShape(Bubble(isMe: isMe))
    }
}

struct TextBubble: View {
    let text: String
    let isMe: Bool

    var body: some View {
        Text(text)
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isMe ? Color.chatBubbleOut : Color.chatBubbleIn)
            .foregroundStyle(isMe ? .white : .primary)
            .clipShape(Bubble(isMe: isMe))
    }
}

// One message row (supports text or product bubbles)
struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isMe { Spacer(minLength: 40) }
            switch message.kind {
            case .text(let t):
                TextBubble(text: t, isMe: message.isMe)
            case .product(let p, note: let note):
                VStack(alignment: .trailing, spacing: 10) {
                    ProductCardBubble(product: p, isMe: message.isMe)
                    if !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(message.isMe ? Color.chatBubbleOut : Color.chatBubbleIn)
                            .foregroundStyle(message.isMe ? .white : .primary)
                            .clipShape(Bubble(isMe: message.isMe))
                    }
                }
            }
            if !message.isMe { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Input bar

struct ChatInputBar: View {
    @Binding var text: String
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle")
                TextField("Type message…", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                Button { /* mic */ } label: { Image(systemName: "mic") }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.systemGray6)))

            Button(action: onSend) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(Circle().fill(Color.chatPrimary))
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Material.bar)
    }
}

// MARK: - Header

struct ChatHeader: View {
    let title: String
    let subtitle: String
    let avatarURL: String?

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Group {
                if let s = avatarURL, let url = URL(string: s) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Image(systemName: "person.fill").resizable().scaledToFit().padding(10)
                        }
                    }
                } else {
                    Image(systemName: "person.fill").resizable().scaledToFit().padding(10)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color(.systemGray5))
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.green)
            }
            Spacer()
            HStack(spacing: 14) {
                Button { /* video */ } label: { Image(systemName: "video.fill") }
                Button { /* call  */ } label: { Image(systemName: "phone.fill") }
                Button { /* notifications */ } label: { Image(systemName: "bell") }
            }
            .font(.title3)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        )
        .padding(.horizontal)
        .padding(.top, 6)
    }
}

// MARK: - Main screen

struct ChatScreenUI: View {
    // Replace with your ChatVM bindings
    @State private var draft = ""

    // sample data
    @State private var messages: [ChatMessage] = [
        .init(isMe: true,  sentAt: Date().addingTimeInterval(-3600), kind: .text("Hi, I have purchased this product")),
        .init(isMe: true,  sentAt: Date().addingTimeInterval(-3550),
              kind: .product(
                .init(title: "Bix Bag Limited…", color: "Brown", imageURL: nil),
                note: "Ahmir has paid $1,100. Click this link Kutuku.com/payment/success/…"
              )),
        .init(isMe: true,  sentAt: Date().addingTimeInterval(-3500), kind: .text("Send it soon ok!")),
        .init(isMe: false, sentAt: Date().addingTimeInterval(-3400), kind: .text("Hi Ahmir, Thanks for buying our product")),
        .init(isMe: false, sentAt: Date().addingTimeInterval(-3300), kind: .text("Your package will be packed soon"))
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ChatHeader(title: "Jhone Endrue", subtitle: "Online", avatarURL: nil)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(messages) { msg in
                                MessageRow(message: msg)
                                    .id(msg.id)
                                // Optional per-message time (example on outgoing)
                                if msg.isMe {
                                    HStack {
                                        Spacer()
                                        Text(timeString(msg.sentAt))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .padding(.trailing, 24)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .onChange(of: messages) { old, new in
                        if let last = messages.last?.id {
                            withAnimation(.easeOut) { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }

                ChatInputBar(text: $draft) {
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    messages.append(ChatMessage(isMe: true, sentAt: Date(), kind: .text(trimmed)))
                    draft = ""
                }
            }
            .navigationTitle("Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { /* back */ } label: { Image(systemName: "chevron.left") }
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
}

// MARK: - Preview

struct ChatScreenUI_Previews: PreviewProvider {
    static var previews: some View {
        ChatScreenUI()
    }
}
