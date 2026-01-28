//
//  PrimaryButtonStyle.swift
//  Vestivia
//
//  Created by William Hunsucker on 7/18/25.
//


import SwiftUI

extension Color {
    // Background Colors
    static let backgroundPrimary = Color(hex: "#FFFFFF")
    static let backgroundSecondary = Color(hex: "#F5F1E8")

    // Primary UI Colors
    static let primaryBlue = Color(hex: "#BFDFFC")
    static let secondaryPink = Color(hex: "#F5C5D5")

    // Accent Colors
    static let accentRed = Color(hex: "#D6302C")
    static let accentNavy = Color(hex: "#003366")
    static let accentTerracotta = Color(hex: "#E07A5F")

    // Supporting & Neutral Colors
    static let neutralCamel = Color(hex: "#C19A6B")
    static let pastelMint = Color(hex: "#A2D5AB")

    // Text Colors
    static let textGray = Color(hex: "#5A5A5A")
}

// MARK: - HEX Color Initializer
extension Color {
    init(hex: String) {
        let trimmedHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: trimmedHex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch trimmedHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.primaryBlue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .shadow(radius: configuration.isPressed ? 0 : 4)
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.accentRed)
            .foregroundColor(.white)
            .cornerRadius(10)
            .shadow(radius: configuration.isPressed ? 0 : 4)
    }
}

