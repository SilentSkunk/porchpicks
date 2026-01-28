import SwiftUI

// Bottom navigation bar ONLY. The owning container (e.g., MainTabView) should
// hold `@State var selectedTab: AppTab` and pass `$selectedTab` here.
// This file uses the project-wide AppTab enum and should not declare its own enum.

struct BottomNavBar: View {
    @Binding var selectedTab: AppTab
    @Binding var navigateToSiblings: Bool
    @Binding var showPatternMatch: Bool

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            Button(action: { navigateToSiblings = true }) {
                NavBarItem(icon: "camera", label: "Sell")
            }
            Spacer()
            Button(action: { selectedTab = .feed }) {
                NavBarItem(icon: "person.2.rectangle.stack", label: "Feed")
            }
            Spacer()
            Button(action: { selectedTab = .shop }) {
                NavBarItem(icon: "magnifyingglass", label: "Shop")
            }
            Spacer()
            Button(action: { selectedTab = .myStore }) {
                NavBarItem(icon: "tag", label: "My Porch")
            }
            Spacer()
            Button(action: { showPatternMatch = true }) {
                NavBarItem(icon: "magnifyingglass.circle", label: "Pattern")
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .background(
            VStack(spacing: 0) {
                Divider().background(Color.black)
                Color(.systemBackground)
            }
        )
    }
}

struct NavBarItem: View {
    let icon: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(label)
                .font(.caption2)
        }
        .foregroundColor(.primary)
    }
}

struct ActionSheetView: View {
    var body: some View {
        Text("Sell Options Coming Soon")
            .font(.title)
            .padding()
    }
}
