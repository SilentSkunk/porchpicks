//
//  PaymentMethodSectionView.swift
//  Exchange
//
//  Created by William Hunsucker on 11/23/25.
//


import SwiftUI

struct PaymentMethodSectionView: View {
    let label: String = "Payment Method"
    let paymentSummary: String?   // Example: "Visa •••• 4242"
    let isValid: Bool             // Whether a valid payment method is set
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 48, height: 32)
                    
                    Image(systemName: iconName)
                        .foregroundColor(.blue)
                        .font(.system(size: 16, weight: .semibold))
                }
                
                // Text stack
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.headline)
                    
                    HStack(spacing: 6) {
                        Text(paymentSummary ?? "Tap to add payment")
                            .font(.subheadline)
                            .foregroundColor(.gray)

                        if isValid && paymentSummary != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 14))
                        }
                    }
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.white)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

extension PaymentMethodSectionView {
    private var iconName: String {
        if let summary = paymentSummary,
           summary.lowercased().contains("visa") {
            return "v.circle.fill"
        }
        if let summary = paymentSummary,
           summary.lowercased().contains("mastercard") {
            return "m.circle.fill"
        }
        if let summary = paymentSummary,
           summary.lowercased().contains("amex") {
            return "a.circle.fill"
        }
        return "creditcard.circle.fill"
    }
}
