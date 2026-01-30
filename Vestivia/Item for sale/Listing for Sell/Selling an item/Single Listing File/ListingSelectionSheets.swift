//
//  ListingSelectionSheets.swift
//  Exchange
//
//  Reusable selection sheet components for listing forms.
//

import SwiftUI

// MARK: - Single Selection Sheet
struct SelectionSheet: View {
    let title: String
    let options: [String]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(options, id: \.self) { option in
                HStack {
                    Text(option)
                    Spacer()
                    if option == selection {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selection = option
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        selection = ""
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Color Selection Sheet (Multi-select, max 2)
struct ColorSelectionSheet: View {
    let title: String
    let options: [(name: String, color: Color)]
    @Binding var selections: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(options, id: \.name) { option in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(option.color)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                        Text(option.name)
                        Spacer()
                        if selections.contains(option.name) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(option.name) }
                }

                Section {
                    Text("Choose up to 2 colors.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        selections.removeAll()
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggle(_ name: String) {
        if let idx = selections.firstIndex(of: name) {
            selections.remove(at: idx)
        } else if selections.count < 2 {
            selections.append(name)
        } else {
            // At max, replace the most recent (index 1) with the new choice
            selections[1] = name
        }
    }
}

// MARK: - Thumbnail View for Image Preview
struct ListingThumbnailView: View {
    let data: Data
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipped()
                    .cornerRadius(10)
            } else {
                ZStack { ProgressView() }
                    .frame(width: 100, height: 100)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
            }
        }
        .task {
            if image == nil {
                // Decode + downscale off the main thread to avoid keyboard jank
                let d = self.data
                await withCheckedContinuation { cont in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let target = CGSize(width: 200, height: 200)
                        var thumb: UIImage?
                        if let ui = UIImage(data: d) {
                            if let prepared = ui.preparingThumbnail(of: target) {
                                thumb = prepared
                            } else {
                                let renderer = UIGraphicsImageRenderer(size: target)
                                thumb = renderer.image { _ in
                                    ui.draw(in: CGRect(origin: .zero, size: target))
                                }
                            }
                        }
                        cont.resume(returning: ())
                        DispatchQueue.main.async { self.image = thumb }
                    }
                }
            }
        }
    }
}
