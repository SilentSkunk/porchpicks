import SwiftUI
import FirebaseAuth

#if DEBUG
extension ListingRoute: CustomStringConvertible {
    var description: String {
        switch self {
        case .listingID(let id):
            return "listingID(\(id))"
        }
    }
}
#endif

// MARK: - Custom Tab Bar

struct TabBarView: View {
    @Binding var selectedTab: AppTab
    var onSell: () -> Void
    var onPattern: () -> Void

    var body: some View {
        HStack {
            Button(action: { onSell() }) {
                NavBarItem(icon: "camera", label: "Sell")
            }
            .frame(maxWidth: .infinity)

            Button(action: { selectedTab = .feed }) {
                NavBarItem(icon: "person.2.square.stack", label: "Feed")
            }
            .frame(maxWidth: .infinity)

            Button(action: { selectedTab = .shop }) {
                NavBarItem(icon: "magnifyingglass", label: "Shop")
            }
            .frame(maxWidth: .infinity)

            Button(action: { selectedTab = .myStore }) {
                NavBarItem(icon: "house.fill", label: "My Porch")
            }
            .frame(maxWidth: .infinity)

            Button(action: { onPattern() }) {
                NavBarItem(icon: "sparkles", label: "Pattern")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 0)
        .frame(maxHeight: 44)
        .padding(.horizontal)
        .background(
            VStack(spacing: 0) {
                Color.black.frame(height: 0.5)
                Color.white
            }
        )
    }
}

// MARK: - MainTabView

struct MainTabView: View {
    @Binding var isLoggedIn: Bool

    @State private var selectedTab: AppTab = .feed

    // Sell flow state
    @State private var numberOfSets: Int = 1
    @State private var brand: String = ""
    @State private var isSiblingSet: Bool = true
    @State private var navigateToSiblingSetup = false
    @State private var navigateToAddListingView = false

    // Centralized navigation for the Shop tab so InstantSearch can push detail routes.
    @StateObject private var coordinator = InstantSearchCoordinator()

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            ZStack {
                Group {
                    switch selectedTab {
                    case .feed:
                        HomeFeedView(
                            selectedTab: $selectedTab,
                            showingSellOptions: .constant(false),
                            navigateToSiblings: .constant(false),
                            isLoggedIn: $isLoggedIn
                        )

                    case .shop:
                        InstantSearchScreen(
                            coordinator: coordinator,
                            selectedTab: $selectedTab,
                            isPresented: .constant(false),
                            showTabBar: true
                        )

                    case .sell:
                        // This tab is launched via the Sell button in the tab bar
                        EmptyView()

                    case .pattern:
                        PatternsView()

                    case .myStore:
                        SellerProfileView(uid: Auth.auth().currentUser?.uid ?? "")
                    }
                }
            }
            // Push ListingDetailView using your app's route type
            .navigationDestination(for: ListingRoute.self) { route in
                switch route {
                case .listingID(let id):
                    ListingDetailContainer(listingId: id)
                        .onAppear {
                            #if DEBUG
                            print("🧭 [MainTabView] navigationDestination resolved → ListingDetail for route: \(ListingRoute.listingID(id))")
                            #endif
                        }
                }
            }
            // Custom tab bar pinned to bottom
            .safeAreaInset(edge: .bottom) {
                TabBarView(
                    selectedTab: $selectedTab,
                    onSell: {
                        // reset sell flow state and kick off the sibling setup flow
                        brand = ""
                        numberOfSets = 1
                        isSiblingSet = false
                        navigateToSiblingSetup = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            navigateToSiblingSetup = true
                        }
                    },
                    onPattern: {
                        selectedTab = .pattern
                    }
                )
                .background(Color.white)
            }
            // Sell flow: sibling setup
            .navigationDestination(isPresented: $navigateToSiblingSetup) {
                SiblingSetupView(
                    numberOfSets: $numberOfSets,
                    brand: $brand,
                    showingBrandPicker: .constant(false),
                    showingValidation: .constant(false),
                    validationMessage: .constant(""),
                    onNext: { _ in
                        navigateToSiblingSetup = false
                        navigateToAddListingView = true
                    }
                )
            }
            // Sell flow: add listing
            .navigationDestination(isPresented: $navigateToAddListingView) {
                AddListingView(
                    numberOfSets: $numberOfSets,
                    brand: $brand,
                    isSiblingSet: $isSiblingSet
                )
            }
        }
        // Handle deep links / push taps to a listing
        .onReceive(NotificationCenter.default.publisher(for: .didSelectListingFromPush)) { notification in
            if let id = notification.userInfo?["listingId"] as? String, !id.isEmpty {
                // ensure we're on the Shop tab so the stack is correct
                selectedTab = .shop
                #if DEBUG
                print("🧭 [MainTabView] push notification – will append route: \(ListingRoute.listingID(id))")
                #endif
                // push the detail into the current navigation stack so the custom tab bar stays
                coordinator.path.append(ListingRoute.listingID(id))
            }
        }
    }
}

// MARK: - Placeholder AddListingView (remove when real view exists)
struct AddListingView: View {
    @Binding var numberOfSets: Int
    @Binding var brand: String
    @Binding var isSiblingSet: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("AddListingView placeholder")
                .font(.headline)
            Text("numberOfSets: \(numberOfSets)")
            Text("brand: \(brand.isEmpty ? "(empty)" : brand)")
            Text("isSiblingSet: \(isSiblingSet ? "true" : "false")")
        }
        .padding()
        .navigationTitle("Add Listing")
    }
}
