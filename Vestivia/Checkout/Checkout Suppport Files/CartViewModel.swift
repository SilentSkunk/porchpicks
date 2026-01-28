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
        guard let address = selectedAddress else {
            print("❌ No address selected")
            return
        }
        guard let firstItem = cartItems.first else {
            print("❌ Cart empty")
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
                print("❌ No shipping rates available")
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
        // TODO: Persist full order to Firestore
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

// ------------------------------------------------------
// MARK: - UserAddress Compatibility (Shipping)
// ------------------------------------------------------
// Temporary shim so Shippo payload can compile until
// state / zip are added to the canonical UserAddress model.

extension UserAddress {
    var state: String {
        ""
    }

    var zip: String {
        ""
    }
}
