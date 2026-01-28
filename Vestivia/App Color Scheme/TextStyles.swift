//
//  TextStyles.swift
//  Vestivia
//
//  Created by William Hunsucker on 7/18/25.
//

import SwiftUI

// MARK: - Text Styles
extension View {
    func headerStyle() -> some View {
        self.font(.title.bold()).foregroundColor(.accentNavy)
    }

    func bodyStyle() -> some View {
        self.font(.body).foregroundColor(.textGray)
    }
}
