//
//  EmptyStateView.swift
//  Exchange
//
//  Reusable empty state view for consistent UI across the app.
//

import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Convenience Initializers
extension EmptyStateView {
    /// Empty state for when there are no items in a list
    static func noItems(
        title: String = "No items yet",
        message: String = "Items will appear here when available.",
        retryAction: (() -> Void)? = nil
    ) -> EmptyStateView {
        EmptyStateView(
            icon: "shippingbox",
            title: title,
            message: message,
            actionTitle: retryAction != nil ? "Refresh" : nil,
            action: retryAction
        )
    }

    /// Empty state for search results
    static func noSearchResults(
        query: String,
        clearAction: (() -> Void)? = nil
    ) -> EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No results found",
            message: "We couldn't find any items matching \"\(query)\".",
            actionTitle: clearAction != nil ? "Clear Search" : nil,
            action: clearAction
        )
    }

    /// Empty state for errors
    static func error(
        message: String,
        retryAction: (() -> Void)? = nil
    ) -> EmptyStateView {
        EmptyStateView(
            icon: "exclamationmark.triangle",
            title: "Something went wrong",
            message: message,
            actionTitle: retryAction != nil ? "Try Again" : nil,
            action: retryAction
        )
    }

    /// Empty state for empty cart
    static func emptyCart(
        shopAction: (() -> Void)? = nil
    ) -> EmptyStateView {
        EmptyStateView(
            icon: "cart",
            title: "Your cart is empty",
            message: "Add items to your cart to get started.",
            actionTitle: shopAction != nil ? "Start Shopping" : nil,
            action: shopAction
        )
    }

    /// Empty state for no likes/picks
    static func noLikes(
        browseAction: (() -> Void)? = nil
    ) -> EmptyStateView {
        EmptyStateView(
            icon: "heart",
            title: "No saved picks yet",
            message: "Items you like will appear here.",
            actionTitle: browseAction != nil ? "Browse Items" : nil,
            action: browseAction
        )
    }

    /// Empty state for no messages
    static func noMessages() -> EmptyStateView {
        EmptyStateView(
            icon: "bubble.left.and.bubble.right",
            title: "No messages",
            message: "Your conversations will appear here."
        )
    }
}

// MARK: - Preview
#if DEBUG
struct EmptyStateView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            EmptyStateView.noItems()
            EmptyStateView.noSearchResults(query: "vintage dress")
            EmptyStateView.error(message: "Network connection failed", retryAction: {})
        }
        .previewDisplayName("Empty States")
    }
}
#endif
