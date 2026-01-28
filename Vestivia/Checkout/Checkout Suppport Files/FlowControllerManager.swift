//
//  FlowControllerManager.swift
//  Exchange
//
//  Created by William Hunsucker on 11/23/25.
//

//
//  FlowControllerManager.swift
//  Exchange
//

import Foundation
import Stripe
import StripePaymentSheet
import FirebaseFunctions
import UIKit

@MainActor
class FlowControllerManager: ObservableObject {
    
    // ------------------------------------------------------
    // MARK: - Published State
    // ------------------------------------------------------
    @Published var flowController: PaymentSheet.FlowController? = nil
    @Published var isLoading: Bool = false
    @Published var lastSelectedOptionDisplay: PaymentSheet.FlowController.PaymentOptionDisplayData? = nil
    @Published var lastDisplayData: PaymentSheet.FlowController.PaymentOptionDisplayData? = nil
    
    private let functions = Functions.functions(region: "us-central1")
    
    // ------------------------------------------------------
    // MARK: - Setup FlowController (customer + ephem key)
    // ------------------------------------------------------
    func prepareFlowController(
        subtotalCents: Int,
        shippingCents: Int,
        address: ShippingAddress,
        prefill: Prefill? = nil
    ) async -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        
        print("💳 [FlowController] Preparing FlowController...")
        
        do {
            let initResult = try await fetchInitData(
                subtotalCents: subtotalCents,
                shippingCents: shippingCents,
                address: address
            )
            
            STPAPIClient.shared.publishableKey = initResult.publishableKey
            
            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "PorchPick"
            configuration.customer = .init(id: initResult.customerId,
                                           ephemeralKeySecret: initResult.ephemeralKey)
            configuration.returnURL = "exchange://stripe-flow-return"
            
            if let p = prefill {
                configuration.defaultBillingDetails.name = p.fullName
                configuration.defaultBillingDetails.phone = p.phone
                configuration.defaultBillingDetails.address.city = p.city
                configuration.defaultBillingDetails.address.country = p.country
                configuration.defaultBillingDetails.address.line1 = p.address
            }
            
            print("💳 [FlowController] Requesting FlowController with PaymentIntent \(initResult.paymentIntent)")
            
            let controller = try await withCheckedThrowingContinuation { continuation in
                PaymentSheet.FlowController.create(
                    paymentIntentClientSecret: initResult.paymentIntent,
                    configuration: configuration
                ) { result in
                    switch result {
                    case .success(let controller):
                        continuation.resume(returning: controller)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            self.flowController = controller
            self.lastDisplayData = controller.paymentOption
            
            print("✅ [FlowController] Ready")
            isLoading = false
            return true
            
        } catch {
            print("❌ [FlowController] Failed: \(error.localizedDescription)")
            isLoading = false
            return false
        }
    }
    
    // ------------------------------------------------------
    // MARK: - Present Payment Options
    // ------------------------------------------------------
    func presentOptions(from vc: UIViewController) async -> PaymentSheet.FlowController.PaymentOptionDisplayData? {
        guard let controller = flowController else {
            print("❌ [FlowController] Cannot present — flowController is nil")
            return nil
        }
        
        print("📲 [FlowController] Presenting payment options...")
        
        return await withCheckedContinuation { continuation in
            controller.presentPaymentOptions(from: vc) {
                continuation.resume(returning: controller.paymentOption)
            }
        }
    }
    
    // ------------------------------------------------------
    // MARK: - Make Payment
    // ------------------------------------------------------
    func confirmPayment(from vc: UIViewController) async -> PaymentSheetResult? {
        guard let controller = flowController else {
            print("❌ [FlowController] Cannot confirm — flowController is nil")
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            controller.confirm(from: vc) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    // ------------------------------------------------------
    // MARK: - Backend Helper
    // ------------------------------------------------------
    private func fetchInitData(
        subtotalCents: Int,
        shippingCents: Int,
        address: ShippingAddress
    ) async throws -> InitData {
        let call = functions.httpsCallable("initFlowController")

        let payload: [String: Any] = [
            "subtotal": subtotalCents,
            "shipping": shippingCents,
            "currency": "usd",
            "address": [
                "line1": address.line1,
                "city": address.city,
                "state": address.state,
                "postal_code": address.postalCode,
                "country": address.country
            ]
        ]

        let result = try await call.call(payload)
        
        guard let dict = result.data as? [String: Any],
              let paymentIntent = dict["paymentIntent"] as? String,
              let ephemeralKey = dict["ephemeralKey"] as? String,
              let customerId = dict["customer"] as? String,
              let publishableKey = dict["publishableKey"] as? String
        else {
            throw NSError(domain: "FlowController", code: -1,
                          userInfo: [NSLocalizedDescriptionKey : "Missing Stripe keys"])
        }
        
        return InitData(
            paymentIntent: paymentIntent,
            ephemeralKey: ephemeralKey,
            customerId: customerId,
            publishableKey: publishableKey
        )
    }
}

// ------------------------------------------------------
// MARK: - Prefill Model
// ------------------------------------------------------
extension FlowControllerManager {
    struct Prefill {
        var fullName: String?
        var phone: String?
        var address: String?
        var city: String?
        var country: String?
    }
    
    struct ShippingAddress {
        let line1: String
        let city: String
        let state: String
        let postalCode: String
        let country: String
    }
}

// ------------------------------------------------------
// MARK: - Initialization Response Model
// ------------------------------------------------------
extension FlowControllerManager {
    struct InitData {
        let paymentIntent: String
        let ephemeralKey: String
        let customerId: String
        let publishableKey: String
    }
}
