//
//  PaymentMethodManager.swift
//  Exchange
//
//  Created by William Hunsucker on 11/7/25.
//

//
//  PaymentMethodManager.swift
//  Exchange
//
//  Created by William Hunsucker on 11/07/25.
//

import Foundation
import SwiftUI
import Combine
import Stripe
import StripePaymentSheet
import FirebaseFunctions

@MainActor
class PaymentMethodManager: ObservableObject {
    struct Prefill {
        var fullName: String?
        var phone: String?
        var address: String?
        var city: String?
        var state: String?
        var postalCode: String?
        var country: String?
    }

    @Published var lastResult: PaymentSheetResult? = nil
    @Published var isLoading = false
    var paymentSheet: PaymentSheet? = nil
    private let functions = Functions.functions(region: "us-central1")

    /// Preloads the PaymentSheet so tapping Payment opens instantly
    func preloadSetupSheet(prefill: Prefill?) async {
        guard !isLoading else { return }
        isLoading = true
        print("💳 [PaymentMethodManager] Preloading SetupSheet...")

        do {
            let result = try await functions.httpsCallable("initSetupSheet").call([:])
            guard let dict = result.data as? [String: Any],
                  let setupIntent = dict["setupIntent"] as? String,
                  let ephemeralKey = dict["ephemeralKey"] as? String,
                  let customerId = dict["customer"] as? String,
                  let publishableKey = dict["publishableKey"] as? String
            else {
                print("❌ [Stripe] Missing keys during preload")
                isLoading = false
                return
            }

            STPAPIClient.shared.publishableKey = publishableKey

            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "PorchPick"
            configuration.customer = .init(id: customerId, ephemeralKeySecret: ephemeralKey)
            configuration.returnURL = "exchange://stripe-setup-complete"
            // Restrict to US-only
            configuration.defaultBillingDetails.address.country = "US"
            configuration.billingDetailsCollectionConfiguration.address = .never

            if let prefill = prefill {
                configuration.defaultBillingDetails.name = prefill.fullName
                configuration.defaultBillingDetails.phone = prefill.phone
                configuration.defaultBillingDetails.address.line1 = prefill.address
                configuration.defaultBillingDetails.address.city = prefill.city
                configuration.defaultBillingDetails.address.state = prefill.state
                configuration.defaultBillingDetails.address.postalCode = prefill.postalCode
                configuration.defaultBillingDetails.address.country = prefill.country
            }

            self.paymentSheet = PaymentSheet(setupIntentClientSecret: setupIntent,
                                             configuration: configuration)

            print("✅ [Stripe] PaymentSheet preloaded")

        } catch {
            print("❌ [Stripe] preload failed: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Launches the Stripe Setup Flow to collect or update payment methods.
    func startSetupFlow(presentingVC: UIViewController, prefill: Prefill?) {
        Task { @MainActor in
            // If first time, preload setup sheet
            if self.paymentSheet == nil {
                await self.preloadSetupSheet(prefill: prefill)
            }

            guard let paymentSheet = self.paymentSheet else {
                print("❌ [Stripe] PaymentSheet unavailable after preload")
                return
            }

            paymentSheet.present(from: presentingVC) { result in
                Task { @MainActor in
                    self.lastResult = result
                    switch result {
                    case .completed:
                        print("✅ [Stripe] Payment method setup completed successfully.")
                    case .canceled:
                        print("⚪️ [Stripe] Payment method setup canceled by user.")
                    case .failed(let error):
                        print("❌ [Stripe] Payment method setup failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    func presentPaymentSheet(from vc: UIViewController) {
        guard let paymentSheet = self.paymentSheet else {
            print("❌ [PaymentMethodManager] No PaymentSheet available to present.")
            return
        }
        paymentSheet.present(from: vc) { result in
            Task { @MainActor in
                self.lastResult = result
            }
        }
    }
}
