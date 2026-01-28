//
//  BubbleTextStyle.swift
//  Exchange
//
//  Created by William Hunsucker on 7/22/25.
//


import SwiftUI

// MARK: - Font & Color Modifiers

struct BubbleTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .foregroundColor(.primary)
    }
}

struct BubbleLabelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption)
            .foregroundColor(.gray)
    }
}

// MARK: - Extensions for Easy Use

extension View {
    func bubbleText() -> some View {
        self.modifier(BubbleTextStyle())
    }

    func bubbleLabel() -> some View {
        self.modifier(BubbleLabelStyle())
    }
}