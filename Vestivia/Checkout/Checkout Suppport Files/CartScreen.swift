//
//  CartScreen.swift
//  Exchange
//
//  Created by William Hunsucker on 11/23/25.
//

import SwiftUI


struct CheckoutTopBar: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HStack {
            Button(action: { dismiss() }, label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(8)
                    .background(Color.white)
                    .clipShape(Circle())
            })
            Spacer()
            Text("Your Cart")
                .font(.system(size: 22, weight: .semibold))
            Spacer()
            Color.clear.frame(width: 32)
        }
        .padding(.horizontal)
        .frame(height: 60)
        .background(.ultraThinMaterial)
    }
}

struct CartItemsSection: View {
    let items: [CartItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            ForEach(items) { item in
                HStack(spacing: 12) {

                    if let id = item.listingId,
                       let uiImg = DiskListingCache.loadHeroImage(for: id) {
                        Image(uiImage: uiImg)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipped()
                            .cornerRadius(12)
                            .frame(maxHeight: .infinity, alignment: .center)
                    } else if let url = URL(string: item.imageName) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                Color(.systemGray5)
                            }
                        }
                        .frame(width: 60, height: 60)
                        .clipped()
                        .cornerRadius(12)
                        .frame(maxHeight: .infinity, alignment: .center)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray5))
                            .frame(width: 60, height: 60)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Text("$\(item.price, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)

                    Spacer()

                }
                .frame(maxHeight: .infinity, alignment: .center)
                .frame(height: 72)
                .padding(8)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
                #if DEBUG
                .onAppear { print("[CartItemsSection] Rendering item") }
                #endif
            }
        }
        .padding(.top, 24)
        .padding(.vertical, 0)
        .padding(.horizontal, 0)
    }
}

struct AddressSection: View {
    let address: String?
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 26))

                VStack(alignment: .leading) {
                    Text("Delivery Address")
                        .font(.subheadline)
                    Text(address ?? "Tap to add address")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        }
    }
}

struct PaymentSection: View {
    let paymentMethod: String?
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundColor(.purple)
                    .font(.system(size: 26))

                VStack(alignment: .leading) {
                    Text("Payment Method")
                        .font(.subheadline)
                    Text(paymentMethod ?? "Tap to add payment method")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        }
    }
}

struct OrderSummarySection: View {
    let subtotal: Double
    let shipping: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Order Summary")
                .font(.headline)

            HStack {
                Text("Subtotal")
                Spacer()
                Text("$\(subtotal, specifier: "%.2f")")
            }

            HStack {
                Text("Shipping")
                Spacer()
                Text("$\(shipping, specifier: "%.2f")")
            }

            Divider()

            HStack {
                Text("Total")
                    .font(.headline)
                Spacer()
                Text("$\(subtotal + shipping, specifier: "%.2f")")
                    .font(.headline)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}

struct CheckoutButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.gradient)
                .cornerRadius(20)
                .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }
}

struct CartScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = CartViewModel()
    @State private var showCheckoutAlert = false
    @State private var checkoutAlertMessage = ""

    var incomingItem: CartItem?

    var body: some View {
        VStack(spacing: 0) {
            CheckoutTopBar()

            if vm.cartItems.isEmpty {
                EmptyStateView.emptyCart {
                    dismiss()
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 24) {

                        CartItemsSection(items: vm.cartItems)
                            .padding(.top, 35)

                    AddressSection(address: vm.selectedAddress?.displayString) {
                        vm.tapAddress()
                    }

                    PaymentSection(paymentMethod: vm.paymentSummary) {
                        #if DEBUG
                        print("[CartScreen] PaymentSection tapped")
                        #endif
                        guard let vc = UIApplication.shared.topMostViewController() else {
                            return
                        }
                        let prefill = PaymentMethodManager.Prefill(
                            fullName: vm.selectedAddress?.fullName,
                            phone: vm.selectedAddress?.phone,
                            address: vm.selectedAddress?.address,
                            city: vm.selectedAddress?.city,
                            state: vm.selectedAddress?.state,
                            postalCode: vm.selectedAddress?.zip,
                            country: vm.selectedAddress?.country
                        )
                        vm.paymentSheetManager.startSetupFlow(presentingVC: vc, prefill: prefill)
                    }

                    OrderSummarySection(
                        subtotal: vm.subtotal,
                        shipping: vm.selectedShippingRate.flatMap { Double($0.amount) } ?? 0
                    )
                    }
                    .padding(.top, -20)
                }

                CheckoutButton(title: vm.isCheckingOut ? "Processing…" : "Checkout") {
                    // Validate required details
                    if vm.selectedAddress == nil && vm.paymentSummary == nil {
                        checkoutAlertMessage = "Please add a delivery address and payment method before checking out."
                        showCheckoutAlert = true
                        return
                    }
                    if vm.selectedAddress == nil {
                        checkoutAlertMessage = "Please add a delivery address before checking out."
                        showCheckoutAlert = true
                        return
                    }
                    if vm.paymentSummary == nil {
                        checkoutAlertMessage = "Please add a payment method before checking out."
                        showCheckoutAlert = true
                        return
                    }

                    // All good — continue checkout
                    if UIApplication.shared.topMostViewController() != nil {
                        vm.checkout()
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $vm.showingAddressForm) {
            AddressFormView { addr in
                let combinedAddress = addr.address2.isEmpty ? addr.address1 : "\(addr.address1), \(addr.address2)"
                let converted = UserAddress(
                    id: UUID().uuidString,
                    fullName: addr.fullName,
                    address: combinedAddress,
                    city: addr.city,
                    state: addr.state,
                    zip: addr.zip,
                    country: "US",
                    phone: addr.phone,
                    isPrimary: true
                )
                Task { await vm.saveAddress(converted) }
            }
        }
        .alert("Missing Information", isPresented: $showCheckoutAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(checkoutAlertMessage)
        }
        .alert("Checkout Error", isPresented: Binding(
            get: { vm.checkoutError != nil },
            set: { if !$0 { vm.checkoutError = nil } }
        )) {
            Button("OK", role: .cancel) { vm.checkoutError = nil }
        } message: {
            Text(vm.checkoutError ?? "")
        }
        .alert("Order Placed!", isPresented: $vm.checkoutSuccess) {
            Button("View Order") {
                // Future: navigate to order details
                dismiss()
            }
            Button("Done", role: .cancel) {
                dismiss()
            }
        } message: {
            if let orderId = vm.completedOrderId {
                Text("Your order has been placed successfully.\n\nOrder ID: \(orderId.prefix(8))...")
            } else {
                Text("Your order has been placed successfully!")
            }
        }
        .onAppear {
            vm.loadCartOnAppear(incoming: incomingItem)
            Task {
                await vm.loadSavedAddress()
                await vm.refreshSavedCardFromBackend()
            }
        }
    }
}

extension UserAddress {
    var displayString: String {
        "\(address), \(city), \(state) \(zip)"
    }
}

extension UIApplication {
    func topMostViewController(base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        if let nav = root as? UINavigationController {
            return topMostViewController(base: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topMostViewController(base: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topMostViewController(base: presented)
        }
        return root
    }
}
#Preview {
    // Sample preview item
    let sample = CartItem(
        id: UUID(),
        listingId: "preview-id",
        sellerId: "seller123",
        title: "Patagonia Jackets & Coats",
        price: 35.00,
        tax: 0.0,
        quantity: 1,
        imageName: "" // Cache lookup will fail, so a placeholder renders
    )

    CartScreen(incomingItem: sample)
}
