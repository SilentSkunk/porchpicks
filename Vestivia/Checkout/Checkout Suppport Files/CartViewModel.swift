//
//  CartViewModel.swift
//  Exchange
//
//  Created by William Hunsucker on 11/23/25.
//

//
//  CartViewModel.swift
//  Exchange
//
//  Created by ChatGPT on 11/23/25.
//

import Foundation
import SwiftUI
import Combine
import StripePaymentSheet
import Stripe
import FirebaseFunctions
import FirebaseFirestore
import FirebaseAuth

@MainActor
class CartViewModel: ObservableObject {
    
    // ------------------------------------------------------
    // MARK: - Published UI State
    // ------------------------------------------------------
    
    // Cart Data (Step 1)
    @Published var cartItems: [CartItem] = []
    
    // Address Data (Step 2 + Step 8)
    @Published var selectedAddress: UserAddress? = nil
    @Published var showingAddressForm: Bool = false
    
    // Payment Data (Step 3, 4, 5, 6)
    @Published var paymentSummary: String? = nil          // "Visa •••• 4242"
    @Published var hasValidPaymentMethod: Bool = false
    @Published var showingPaymentSheet: Bool = false      // Step 4 OR Step 5
    @Published var showingPaymentOptions: Bool = false    // Step 5
    
    // Checkout (Step 9)
    @Published var isCheckingOut: Bool = false
    @Published var checkoutError: String? = nil

    // Added for selected shipping rate
    @Published var selectedShippingRate: ShippoRate? = nil
    
    // Managers (Step 4 + Step 5)
    let paymentSheetManager = PaymentMethodManager()          // PaymentSheet
    let flowControllerManager = FlowControllerManager()       // FlowController
    
    
    // ------------------------------------------------------
    // MARK: - Initialization
    // ------------------------------------------------------
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        observeStripeCallbacks()
    }

    func injectIncomingItem(_ item: CartItem?) {
        guard let item else { return }
        if !cartItems.contains(where: { $0.id == item.id }) {
            cartItems.insert(item, at: 0)
        }
    }

    func loadCartOnAppear(incoming: CartItem?) {
        injectIncomingItem(incoming)
    }
    
    
    // ------------------------------------------------------
    // MARK: - Listening to Stripe Events (Step 6)
    // ------------------------------------------------------
    
    private func observeStripeCallbacks() {
        
        // Listen for PaymentSheet results (Step 4)
        paymentSheetManager.$lastResult
            .sink { [weak self] result in
                guard let self else { return }
                self.handlePaymentSheetResult(result)
            }
            .store(in: &cancellables)
        
        // Listen for FlowController option updates (Step 5)
        flowControllerManager.$lastDisplayData
            .sink { [weak self] displayData in
                guard let self else { return }
                self.updatePaymentSummary(from: displayData)
            }
            .store(in: &cancellables)
    }
    
    
    // ------------------------------------------------------
    // MARK: - SUMMARY UPDATE: PaymentSheet (Step 4)
    // ------------------------------------------------------
    
    private func handlePaymentSheetResult(_ result: PaymentSheetResult?) {
        guard let result = result else { return }
        
        switch result {
        case .completed:
            print("✅ PaymentSheet completed")
            Task { await refreshSavedCardFromBackend() }
        case .canceled:
            print("⚪️ PaymentSheet canceled")
        case .failed(let error):
            print("❌ PaymentSheet failed: \(error)")
        }
    }
    
    
    // ------------------------------------------------------
    // MARK: - SUMMARY UPDATE: FlowController (Step 5)
    // ------------------------------------------------------
    
    private func updatePaymentSummary(from display: PaymentSheet.FlowController.PaymentOptionDisplayData?) {
        guard let display else {
            paymentSummary = nil
            hasValidPaymentMethod = false
            return
        }
        
        paymentSummary = display.label   // Stripe gives "Visa •••• 4242"
        hasValidPaymentMethod = true
    }
    
    
    // ------------------------------------------------------
    // MARK: - BACKEND SUMMARY REFRESH (Step 6)
    // ------------------------------------------------------
    
    func refreshSavedCardFromBackend() async {
        print("🔄 Refreshing saved payment method…")
        
        do {
            // When you build it: hit the Cloud Function "getSavedCardSummary"
            let summary = try await PaymentMethodManager.fetchSavedCardSummary()
            
            if let summary {
                paymentSummary = "\(summary.brand.capitalized) •••• \(summary.last4)"
                hasValidPaymentMethod = true
            } else {
                paymentSummary = nil
                hasValidPaymentMethod = false
            }
        } catch {
            print("❌ Error refreshing saved card: \(error)")
        }
    }
    
    
    // ------------------------------------------------------
    // MARK: - Computed Values for Checkout UI
    // ------------------------------------------------------
    
    var subtotal: Double {
        cartItems.reduce(0) { $0 + ($1.price * Double($1.quantity)) }
    }
    
    var total: Double {
        subtotal + (Double(selectedShippingRate?.amount ?? "0") ?? 0)
    }

    // ------------------------------------------------------
    // MARK: - Address Validation
    // ------------------------------------------------------

    private static let validUSStates: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY", "DC"
    ]

    func validateAddressForShipping(_ address: UserAddress) -> String? {
        // Check required fields
        if address.fullName.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Full name is required"
        }
        if address.address.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Street address is required"
        }
        if address.city.trimmingCharacters(in: .whitespaces).isEmpty {
            return "City is required"
        }

        // Validate state
        let stateUpper = address.state.trimmingCharacters(in: .whitespaces).uppercased()
        if stateUpper.isEmpty {
            return "State is required"
        }
        if !Self.validUSStates.contains(stateUpper) {
            return "Invalid US state: \(address.state)"
        }

        // Validate ZIP code (5 digits or 5+4 format)
        let zipTrimmed = address.zip.trimmingCharacters(in: .whitespaces)
        if zipTrimmed.isEmpty {
            return "ZIP code is required"
        }
        let zipPattern = #"^\d{5}(-\d{4})?$"#
        if zipTrimmed.range(of: zipPattern, options: .regularExpression) == nil {
            return "Invalid ZIP code format"
        }

        return nil
    }

    // ------------------------------------------------------
    // MARK: - UI Actions (Step 1–3)
    // ------------------------------------------------------
    
    func tapAddress() {
        showingAddressForm = true
    }
    
    func tapPayment() {
        showingPaymentOptions = true
    }

    // ------------------------------------------------------
    // MARK: - Address Integration (Step 8)
    // ------------------------------------------------------
    func loadSavedAddress() async {
        do {
            if let addr = try await AddressManager.shared.loadPrimaryAddress() {
                self.selectedAddress = addr
            }
        } catch {
            print("Address load error: \(error)")
        }
    }

    func saveAddress(_ address: UserAddress) async {
        do {
            try await AddressManager.shared.savePrimaryAddress(address)
            self.selectedAddress = address
        } catch {
            print("Address save error: \(error)")
        }
    }

    // ------------------------------------------------------
    // MARK: - PaymentSheet Interaction (Step 4)
    // ------------------------------------------------------
    func openPaymentSheet(from vc: UIViewController) {
        showingPaymentSheet = true
        paymentSheetManager.presentPaymentSheet(from: vc)
    }

    // ------------------------------------------------------
    // MARK: - Payment Options (Step 5)
    // ------------------------------------------------------
    func openPaymentOptions(from vc: UIViewController) async {
        showingPaymentOptions = false
        if let display = await flowControllerManager.presentOptions(from: vc) {
            self.updatePaymentSummary(from: display)
        }
    }
    
    
    // ------------------------------------------------------
    // MARK: - Checkout (Step 9)
    // ------------------------------------------------------
    
    func checkout() {
        Task {
            await performCheckout()
        }
    }

    private func performCheckout() async {
        checkoutError = nil

        guard let address = selectedAddress else {
            checkoutError = "No address selected"
            return
        }
        guard let firstItem = cartItems.first else {
            checkoutError = "Cart is empty"
            return
        }

        // Validate address before calling shipping API
        if let validationError = validateAddressForShipping(address) {
            checkoutError = validationError
            return
        }

        isCheckingOut = true
        defer { isCheckingOut = false }

        do {
            // 1️⃣ Get shipping rates from Shippo
            let ratesResult = try await getShippingRates(
                toAddress: address,
                listingId: firstItem.listingId ?? ""
            )

            guard let cheapestRate = ratesResult.rates
                .sorted(by: { (Double($0.amount) ?? 0) < (Double($1.amount) ?? 0) })
                .first
            else {
                checkoutError = "No shipping rates available for this address"
                return
            }

            selectedShippingRate = cheapestRate
            print("💰 Selected shipping: $\(cheapestRate.amount)")

            // 2️⃣ Confirm Stripe payment FIRST
            guard let vc = UIApplication.shared.topMostViewController() else {
                print("❌ No view controller for Stripe")
                return
            }

            let paymentResult = await flowControllerManager.confirmPayment(from: vc)

            guard case .completed = paymentResult else {
                print("⚠️ Payment not completed — aborting shipment")
                return
            }

            print("✅ Payment completed!")

            // 3️⃣ Purchase shipping label AFTER payment
            let label = try await purchaseLabel(
                shipmentId: ratesResult.shipmentId,
                rateId: cheapestRate.objectId
            )

            print("📦 Label purchased: \(label.trackingNumber)")

            // 4️⃣ Save order
            try await saveOrder(
                trackingNumber: label.trackingNumber,
                shippingRate: cheapestRate,
                label: label
            )

        } catch {
            print("❌ Checkout failed: \(error)")
            checkoutError = "Checkout failed: \(error.localizedDescription)"
        }
    }

    // ------------------------------------------------------
    // MARK: - Shippo Integration
    // ------------------------------------------------------

    private func getShippingRates(
        toAddress: UserAddress,
        listingId: String
    ) async throws -> ShippoRatesResponse {

        let functions = Functions.functions(region: "us-central1")

        let payload: [String: Any] = [
            "to": [
                "fullName": toAddress.fullName,
                "address": toAddress.address,
                "city": toAddress.city,
                "state": toAddress.state,
                "zip": toAddress.zip,
                "country": toAddress.country
            ],
            "listingId": listingId
        ]

        let result = try await functions
            .httpsCallable("ShippoShipmentGetRates")
            .call(payload)

        guard
            let dict = result.data as? [String: Any],
            let shipmentId = dict["shipmentId"] as? String,
            let ratesArray = dict["rates"] as? [[String: Any]]
        else {
            throw NSError(domain: "Shippo", code: -1)
        }

        let rates = ratesArray.compactMap { rateDict -> ShippoRate? in
            guard
                let objectId = rateDict["object_id"] as? String,
                let amount = rateDict["amount"] as? String
            else { return nil }

            return ShippoRate(
                objectId: objectId,
                servicelevelName: rateDict["servicelevel_name"] as? String,
                amount: amount,
                currency: rateDict["currency"] as? String ?? "USD",
                estimatedDays: rateDict["estimated_days"] as? Int,
                provider: rateDict["provider"] as? String ?? "USPS"
            )
        }

        return ShippoRatesResponse(shipmentId: shipmentId, rates: rates)
    }

    private func purchaseLabel(
        shipmentId: String,
        rateId: String
    ) async throws -> ShippoLabel {

        let functions = Functions.functions(region: "us-central1")

        let payload: [String: Any] = [
            "shipmentId": shipmentId,
            "rateId": rateId
        ]

        let result = try await functions
            .httpsCallable("buyShippoLabel")
            .call(payload)

        guard
            let dict = result.data as? [String: Any],
            let trackingNumber = dict["trackingNumber"] as? String,
            let labelUrl = dict["labelUrl"] as? String
        else {
            throw NSError(domain: "Shippo", code: -1)
        }

        return ShippoLabel(
            trackingNumber: trackingNumber,
            labelUrl: labelUrl,
            carrier: dict["carrier"] as? String ?? "USPS"
        )
    }

    @Published var checkoutSuccess: Bool = false
    @Published var completedOrderId: String? = nil

    private func saveOrder(
        trackingNumber: String,
        shippingRate: ShippoRate,
        label: ShippoLabel
    ) async throws {
        print("""
        💾 Saving order
        - Tracking: \(trackingNumber)
        - Shipping: \(shippingRate.amount) \(shippingRate.currency)
        - Carrier: \(label.carrier)
        """)

        guard let buyerId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Order", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        guard let address = selectedAddress else {
            throw NSError(domain: "Order", code: 400, userInfo: [NSLocalizedDescriptionKey: "No shipping address"])
        }

        let db = Firestore.firestore()
        let orderId = UUID().uuidString

        // Serialize cart items
        let itemsData: [[String: Any]] = cartItems.map { item in
            [
                "id": item.id,
                "listingId": item.listingId ?? "",
                "sellerId": item.sellerId ?? "",
                "title": item.title,
                "price": item.price,
                "quantity": item.quantity,
                "imageUrl": item.imageName ?? ""
            ]
        }

        // Get seller ID from first item (single-seller checkout)
        let sellerId = cartItems.first?.sellerId ?? ""

        // Build order document
        let orderData: [String: Any] = [
            "orderId": orderId,
            "buyerId": buyerId,
            "sellerId": sellerId,
            "items": itemsData,
            "subtotal": subtotal,
            "shippingAmount": Double(shippingRate.amount) ?? 0,
            "shippingCurrency": shippingRate.currency,
            "total": total,
            "status": "pending_shipment",
            "trackingNumber": trackingNumber,
            "carrier": label.carrier,
            "labelUrl": label.labelUrl,
            "shippingService": shippingRate.servicelevelName ?? "Standard",
            "estimatedDays": shippingRate.estimatedDays ?? 0,
            "shippingAddress": [
                "fullName": address.fullName,
                "address": address.address,
                "city": address.city,
                "state": address.state,
                "zip": address.zip,
                "country": address.country,
                "phone": address.phone
            ],
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        // Save to orders collection
        let orderRef = db.collection("orders").document(orderId)

        // Also create references in buyer's and seller's order subcollections
        let buyerOrderRef = db.collection("users").document(buyerId).collection("orders").document(orderId)
        let sellerOrderRef = sellerId.isEmpty ? nil : db.collection("users").document(sellerId).collection("orders").document(orderId)

        // Use batch write for atomicity
        let batch = db.batch()
        batch.setData(orderData, forDocument: orderRef)
        batch.setData(orderData, forDocument: buyerOrderRef)
        if let sellerRef = sellerOrderRef {
            batch.setData(orderData, forDocument: sellerRef)
        }

        try await batch.commit()
        print("✅ Order saved to Firestore with ID: \(orderId)")

        // Update UI state
        await MainActor.run {
            self.checkoutSuccess = true
            self.completedOrderId = orderId
            self.cartItems.removeAll() // Clear cart after successful checkout
        }
    }
}

extension PaymentMethodManager {
    static func fetchSavedCardSummary() async throws -> (brand: String, last4: String)? {
        let functions = Functions.functions(region: "us-central1")
        let result = try await functions.httpsCallable("getSavedCardSummary").call([:])

        guard
            let dict = result.data as? [String: Any],
            let hasSaved = dict["hasSavedPaymentMethod"] as? Bool,
            hasSaved,
            let summary = dict["paymentMethodSummary"] as? [String: Any],
            let brand = summary["brand"] as? String,
            let last4 = summary["last4"] as? String
        else {
            return nil
        }

        return (brand, last4)
    }
}

// ------------------------------------------------------
// MARK: - Shippo Models
// ------------------------------------------------------

struct ShippoRatesResponse {
    let shipmentId: String
    let rates: [ShippoRate]
}

struct ShippoRate {
    let objectId: String
    let servicelevelName: String?
    let amount: String
    let currency: String
    let estimatedDays: Int?
    let provider: String
}


struct ShippoLabel {
    let trackingNumber: String
    let labelUrl: String
    let carrier: String
}

