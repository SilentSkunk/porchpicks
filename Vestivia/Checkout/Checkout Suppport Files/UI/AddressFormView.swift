//
//  AddressFormView.swift
//  Exchange
//
//  Created by William Hunsucker on 10/31/25.
//

import SwiftUI

private let usStates: [String] = [
    "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA",
    "HI","ID","IL","IN","IA","KS","KY","LA","ME","MD",
    "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
    "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC",
    "SD","TN","TX","UT","VT","VA","WA","WV","WI","WY"
]

struct AddressFormView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var fullName: String = ""
    @State private var addressLine: String = ""
    @State private var addressLine2: String = ""
    @State private var city: String = ""
    @State private var state: String = "AL"
    @State private var zip: String = ""
    @State private var phone: String = ""
    @State private var makePrimary: Bool = true
    
    var onSave: ((AddressFormData) -> Void)?
    
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
                
                Text("Address")
                    .font(.system(size: 18, weight: .semibold))
                
                Spacer()
                
                // spacer to balance back button
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // Name
                    Text("Name")
                        .font(.system(size: 14, weight: .semibold))
                    
                    RoundedField(text: $fullName, placeholder: "Full name")
                    
                    Text("Street Address")
                        .font(.system(size: 14, weight: .semibold))

                    RoundedField(text: $addressLine, placeholder: "Street Address Line 1")

                    RoundedField(text: $addressLine2, placeholder: "Street Address Line 2 (Optional)")
                    
                    Text("City")
                        .font(.system(size: 14, weight: .semibold))
                    RoundedField(text: $city, placeholder: "City")

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
                    RoundedField(text: $zip, placeholder: "ZIP Code", keyboard: .numberPad)
                    
                    // Phone
                    Text("Phone Number")
                        .font(.system(size: 14, weight: .semibold))

                    RoundedField(text: $phone, placeholder: "+1 (555) 555-5555", keyboard: .phonePad)

                    // Primary toggle
                    HStack {
                        Text("Save as primary address")
                            .font(.system(size: 14))
                        Spacer()
                        Toggle("", isOn: $makePrimary)
                            .labelsHidden()
                    }
                    .padding(.vertical, 4)
                    
                    Spacer(minLength: 12)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            
            // Bottom button
            Button {
                let data = AddressFormData(
                    fullName: fullName,
                    address1: addressLine,
                    address2: addressLine2,
                    city: city,
                    state: state,
                    zip: zip,
                    phone: phone,
                    isPrimary: makePrimary
                )
                onSave?(data)
                if makePrimary {
                    let combinedAddress = addressLine2.isEmpty ? addressLine : "\(addressLine), \(addressLine2)"
                    let userAddress = UserAddress(
                        id: "main",
                        fullName: fullName,
                        address: combinedAddress,
                        city: city,
                        state: state,
                        zip: zip,
                        country: "United States",
                        phone: phone,
                        isPrimary: true
                    )
                    Task {
                        try? await AddressManager.shared.savePrimaryAddress(userAddress)
                    }
                }
                dismiss()
            } label: {
                Text("Save Address")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.purple)
                    .cornerRadius(16)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
            }
        }
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea(edges: .bottom)
    }
}

struct RoundedField: View {
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

struct AddressFormData {
    let fullName: String
    let address1: String
    let address2: String
    let city: String
    let state: String
    let zip: String
    let phone: String
    let isPrimary: Bool
}

#Preview {
    AddressFormView()
}
