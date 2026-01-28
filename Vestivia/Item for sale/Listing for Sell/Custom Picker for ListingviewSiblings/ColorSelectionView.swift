//
//  ColorSelectionView.swift
//  Exchange
//
//  Created by William Hunsucker on 7/22/25.
//


import SwiftUI

struct ColorSelectionView: View {
    @Binding var selectedColors: Set<String>
    @Environment(\.dismiss) var dismiss

    private let colorOptions: [(name: String, color: Color)] = [
        ("Red", .red), ("Pink", .pink), ("Orange", .orange), ("Yellow", .yellow),
        ("Green", .green), ("Blue", .blue), ("Purple", .purple), ("Gold", .yellow),
        ("Silver", .gray.opacity(0.5)), ("Black", .black), ("Gray", .gray),
        ("White", .white), ("Cream", Color(red: 1, green: 0.95, blue: 0.8)),
        ("Brown", .brown), ("Tan", Color(red: 0.82, green: 0.7, blue: 0.5))
    ]

    var body: some View {
        NavigationView {
            List {
                ForEach(colorOptions, id: \.name) { option in
                    Button(action: {
                        if selectedColors.contains(option.name) {
                            selectedColors.remove(option.name)
                        } else if selectedColors.count < 2 {
                            selectedColors.insert(option.name)
                        }
                    }) {
                        HStack {
                            Circle()
                                .fill(option.color)
                                .frame(width: 20, height: 20)
                            Text(option.name)
                                .bodyStyle()
                            Spacer()
                            if selectedColors.contains(option.name) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.pink)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Colors")
            .headerStyle()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
