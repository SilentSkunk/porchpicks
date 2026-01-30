//
//  SellerShippingAddressView.swift
//  Exchange
//
//  Allows sellers to configure their shipping/return address for Shippo.
//

import SwiftUI

private let usStates: [String] = [
    "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA",
    "HI","ID","IL","IN","IA","KS","KY","LA","ME","MD",
    "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
    "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC",
    "SD","TN","TX","UT","VT","VA","WA","WV","WI","WY"
]

struct SellerShippingAddressView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var fullName: String = ""
    @State private var addressLine: String = ""
    @State private var city: String = ""
    @State private var state: String = "AL"
    @State private var zip: String = ""
    @State private var phone: String = ""

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showSavedAlert = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.black)
                        .padding(8)
                        .background(Color.white)
                        .clipShape(Circle())
                }

                Spacer()

                Text("Shipping Address")
                    .font(.system(size: 18, weight: .semibold))

                Spacer()

                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if isLoading {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        Text("This address will be used as the return/sender address when buyers purchase your listings.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)

                        // Name
                        Text("Full Name")
                            .font(.system(size: 14, weight: .semibold))

                        ShippingRoundedField(text: $fullName, placeholder: "Your name or business name")

                        Text("Street Address")
                            .font(.system(size: 14, weight: .semibold))

                        ShippingRoundedField(text: $addressLine, placeholder: "Street Address")

                        Text("City")
                            .font(.system(size: 14, weight: .semibold))
                        ShippingRoundedField(text: $city, placeholder: "City")

                        Text("State")
                            .font(.system(size: 14, weight: .semibold))
                        Picker("State", selection: $state) {
                            ForEach(usStates, id: \.self) { st in
                                Text(st).tag(st)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxHeight: 150)
                        .clipped()
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )

                        Text("ZIP Code")
                            .font(.system(size: 14, weight: .semibold))
                        ShippingRoundedField(text: $zip, placeholder: "ZIP Code", keyboard: .numberPad)

                        Text("Phone Number")
                            .font(.system(size: 14, weight: .semibold))
                        ShippingRoundedField(text: $phone, placeholder: "+1 (555) 555-5555", keyboard: .phonePad)

                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                        }

                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                // Bottom button
                Button {
                    saveAddress()
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isSaving ? "Saving..." : "Save Shipping Address")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isFormValid ? Color.blue : Color.gray)
                    .cornerRadius(16)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                }
                .disabled(!isFormValid || isSaving)
            }
        }
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea(edges: .bottom)
        .task {
            await loadExistingAddress()
        }
        .alert("Address Saved", isPresented: $showSavedAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your shipping address has been saved. Buyers can now purchase your listings.")
        }
    }

    private var isFormValid: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !addressLine.trimmingCharacters(in: .whitespaces).isEmpty &&
        !city.trimmingCharacters(in: .whitespaces).isEmpty &&
        !zip.trimmingCharacters(in: .whitespaces).isEmpty &&
        zip.trimmingCharacters(in: .whitespaces).count >= 5
    }

    private func loadExistingAddress() async {
        do {
            if let existing = try await AddressManager.shared.loadSellerShippingAddress() {
                fullName = existing.fullName
                addressLine = existing.address
                city = existing.city
                state = existing.state.isEmpty ? "AL" : existing.state
                zip = existing.zip
                phone = existing.phone
            }
        } catch {
            #if DEBUG
            print("[SellerShipping] Error loading address: \(error)")
            #endif
        }
        isLoading = false
    }

    private func saveAddress() {
        guard isFormValid else { return }
        isSaving = true
        errorMessage = nil

        let address = UserAddress(
            id: "shipping",
            fullName: fullName.trimmingCharacters(in: .whitespaces),
            address: addressLine.trimmingCharacters(in: .whitespaces),
            city: city.trimmingCharacters(in: .whitespaces),
            state: state,
            zip: zip.trimmingCharacters(in: .whitespaces),
            country: "US",
            phone: phone.trimmingCharacters(in: .whitespaces),
            isPrimary: false
        )

        Task {
            do {
                try await AddressManager.shared.saveSellerShippingAddress(address)
                await MainActor.run {
                    isSaving = false
                    showSavedAlert = true
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save address. Please try again."
                }
            }
        }
    }
}

private struct ShippingRoundedField: View {
    @Binding var text: String
    var placeholder: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboard)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
    }
}

#Preview {
    SellerShippingAddressView()
}
