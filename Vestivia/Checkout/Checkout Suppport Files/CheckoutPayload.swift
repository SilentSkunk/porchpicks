//
//  CheckoutPayload.swift
//  Exchange
//
//  Created by William Hunsucker on 10/31/25.
//


import Foundation
import FirebaseAuth
import FirebaseFunctions

struct CheckoutPayload {
    let amountCents: Int
    let listingId: String
    let sellerId: String
    let shipping: [String: Any]?
}

final class CheckoutService {
    static let shared = CheckoutService()
    private let functions = Functions.functions()

    private init() {}

    func createPaymentIntent(
        payload: CheckoutPayload,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in."])))
            return
        }

        var data: [String: Any] = [
            "amount": payload.amountCents,
            "currency": "usd",
            "listingId": payload.listingId,
            "sellerId": payload.sellerId,
            "buyerId": uid
        ]

        if let shipping = payload.shipping {
            data["shipping"] = shipping
        }

        functions.httpsCallable("createPaymentIntent").call(data) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard
                let dict = result?.data as? [String: Any],
                let clientSecret = dict["clientSecret"] as? String
            else {
                completion(.failure(NSError(domain: "stripe", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing clientSecret"])))
                return
            }
            completion(.success(clientSecret))
        }
    }
}
