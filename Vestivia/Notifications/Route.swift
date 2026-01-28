//
//  Route.swift
//  Exchange
//
//  Created by William Hunsucker on 9/23/25.
//

import SwiftUI
import Foundation

// A lightweight, decoupled loader signature to avoid type dependencies here.
typealias ListingDetailLoader = (String) async throws -> ListingDetailProps

// Default loader used by RootView. Replace this with your real data service implementation.
private func defaultListingDetailLoader(id: String) async throws -> ListingDetailProps {
    // TODO: wire this to your production service (Algolia/Firestore + Cloudflare signed URL).
    // Temporary placeholder so this module compiles cleanly.
    return ListingDetailProps(
        listingId: id,
        title: "",
        brand: "",
        price: "",
        heroURL: nil
    )
}

struct ListingDetailBridgeView: View {
    let listingId: String
    let fetch: ListingDetailLoader

    @State private var props: ListingDetailProps?
    @State private var hasError = false

    var body: some View {
        Group {
            if let props {
                ListingDetailView(props: props)
            } else if hasError {
                Text("Failed to load listing details.")
            } else {
                ProgressView("Loading…")
            }
        }
        .task {
            do {
                props = try await fetch(listingId)
            } catch {
                hasError = true
            }
        }
    }
}

// MARK: - Notification helper
/// Tiny factory you can call from your notification tap handler to build the bridge view.
/// Example usage:
///   NavigationLink(value: Route.listingDetail(id)) { ... }
/// or present it in any container:
///   ListingDetailBridgeView(listingId: id, fetch: notificationsListingDetailLoader())

func notificationsListingDetailLoader() -> ListingDetailLoader {
    defaultListingDetailLoader
}

/**
 Convenience factory for notification flows (or any caller) that wants to
 quickly present a Listing Detail screen with minimal data on hand.

 Usage:
   let view = makeListingDetailAnyView(listingId: someId)
   // push/present `view` as needed
*/
public func makeListingDetailAnyView(listingId: String) -> AnyView {
    let props = ListingDetailProps(
        listingId: listingId,     // <- now valid
        title: "",
        brand: "",
        price: "",
        heroURL: nil
    )
    return AnyView(ListingDetailContainer(listingId: listingId))
}
