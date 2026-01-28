//
//  AddListingViewSingle.swift
//  Exchange
//
//  Created by William Hunsucker on 7/28/25.
//

import SwiftUI
import PhotosUI

struct AddListingViewSingle: View {
    let selectedBrand: String
    let patternJPEGData: Data?
    @StateObject private var viewModel = ListingViewModel()
    @ObservedObject private var fields = ListingFields.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingImagePicker = false
    @State private var selectedUIImage: UIImage?
    @State private var isShowingCategoryPicker = false
    @State private var isShowingSizePicker = false
    @State private var isShowingConditionPicker = false
    @State private var isShowingGenderPicker = false
    @State private var isShowingColorPicker = false
    @State private var isSubmitting = false
    // Holds only dollars (no cents) – always shows as $<digits>.00
    @State private var priceDigits: String = "0"
    // Keyboard management
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var priceFieldFocused: Bool

    // Dismiss any active text input (esp. price field)
    private func endEditing() {
        priceFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // Dynamic size options: use shoe sizes when the user picks Accessories → Shoes
    private var currentSizeOptions: [String] {
        if fields.selectedSubcategory == "Shoes" || fields.selectedCategory == "Shoes" {
            // Map tuple list to plain names
            return ListingFields.shared.shoeSizeOptions.map { $0.name }
        } else {
            return ListingFields.shared.sizes
        }
    }

    init(selectedBrand: String, patternJPEGData: Data? = nil) {
        self.selectedBrand = selectedBrand
        self.patternJPEGData = patternJPEGData
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                // Images Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Images")
                        .font(.headline)
                    
                    if viewModel.selectedImagesData.isEmpty {
                        Text("No images selected")
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(viewModel.selectedImagesData.enumerated()), id: \.offset) { _, imageData in
                                    ThumbnailView(data: imageData)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    Button(action: {
                        endEditing()
                        isShowingImagePicker = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Image")
                        }
                    }
                    .buttonStyle(.bordered)
                    .sheet(isPresented: $isShowingImagePicker) {
                        ImagePicker { images in
                            for image in images {
                                viewModel.addImage(image)
                            }
                            isShowingImagePicker = false
                        }
                    }
                }
                
                // Brand Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Brand")
                        .font(.headline)
                    Text(selectedBrand)
                        .font(.subheadline)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                }
                
                // Category Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.headline)
                    
                    Button(action: {
                        endEditing()
                        isShowingCategoryPicker = true
                    }) {
                        HStack {
                            let categoryDisplay = fields.selectedCategory.isEmpty
                                ? "Select Category"
                                : (fields.selectedSubcategory.isEmpty
                                   ? fields.selectedCategory
                                   : "\(fields.selectedCategory), \(fields.selectedSubcategory)")
                            Text(categoryDisplay)
                                .foregroundColor(fields.selectedCategory.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                    .sheet(isPresented: $isShowingCategoryPicker) {
                        CategoryPickerView(
                            isPresented: $isShowingCategoryPicker,
                            selectedCategory: $fields.selectedCategory,
                            selectedSubcategory: $fields.selectedSubcategory
                        )
                    }
                }
                
                // Description Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.headline)
                    TextEditor(text: $viewModel.description)
                        .frame(height: 100)
                        .padding(4)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                }
                
                // Details Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Details")
                        .font(.headline)
                    // Size
                    Button(action: {
                        endEditing()
                        isShowingSizePicker = true
                    }) {
                        HStack {
                            Text(fields.selectedSize.isEmpty ? "Size" : fields.selectedSize)
                                .foregroundColor(fields.selectedSize.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                    .sheet(isPresented: $isShowingSizePicker) {
                        SelectionSheet(
                            title: "Size",
                            options: currentSizeOptions,
                            selection: $fields.selectedSize
                        )
                    }

                    // Condition
                    Button(action: {
                        endEditing()
                        isShowingConditionPicker = true
                    }) {
                        HStack {
                            Text(fields.selectedCondition.isEmpty ? "Condition" : fields.selectedCondition)
                                .foregroundColor(fields.selectedCondition.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                    .sheet(isPresented: $isShowingConditionPicker) {
                        SelectionSheet(
                            title: "Condition",
                            options: fields.conditions,
                            selection: $fields.selectedCondition
                        )
                    }

                    // Gender
                    Button(action: {
                        endEditing()
                        isShowingGenderPicker = true
                    }) {
                        HStack {
                            Text(fields.selectedGender.isEmpty ? "Gender" : fields.selectedGender)
                                .foregroundColor(fields.selectedGender.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                    .sheet(isPresented: $isShowingGenderPicker) {
                        SelectionSheet(
                            title: "Gender",
                            options: fields.genders,
                            selection: $fields.selectedGender
                        )
                    }
                    // Color (allow picking up to 2)
                    Button(action: {
                        endEditing()
                        isShowingColorPicker = true
                    }) {
                        HStack(spacing: 12) {
                            // Show swatches (up to two)
                            if fields.selectedColors.isEmpty {
                                Circle()
                                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                                    .frame(width: 18, height: 18)
                            } else {
                                ForEach(fields.selectedColors.prefix(2), id: \.self) { name in
                                    if let swatch = fields.colorOptions.first(where: { $0.name == name })?.color {
                                        Circle()
                                            .fill(swatch)
                                            .frame(width: 18, height: 18)
                                            .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                                    }
                                }
                            }
                            let label = fields.selectedColors.isEmpty ? "Color" : fields.selectedColors.prefix(2).joined(separator: ", ")
                            Text(label)
                                .foregroundColor(fields.selectedColors.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                    .sheet(isPresented: $isShowingColorPicker) {
                        ColorSelectionSheet(
                            title: "Color",
                            options: fields.colorOptions,
                            selections: $fields.selectedColors
                        )
                    }
                // Listing Price – static "$" and ".00", edit dollars only
                HStack(spacing: 6) {
                    // Gray when empty/zero, black when typing a non-zero value
                    let activeColor: Color = (priceDigits == "0" || priceDigits.isEmpty) ? .secondary : .primary

                    Text("$")
                        .foregroundColor(activeColor)

                    TextField("0", text: Binding(
                        get: { (priceFieldFocused && priceDigits == "0") ? "" : priceDigits },
                        set: { raw in
                            // Keep only digits and normalize leading zeros
                            let digitsOnly = raw.filter { $0.isNumber }
                            if digitsOnly.isEmpty {
                                priceDigits = "0"
                            } else if digitsOnly.allSatisfy({ $0 == "0" }) {
                                priceDigits = "0"
                            } else {
                                priceDigits = String(digitsOnly.drop(while: { $0 == "0" }))
                            }
                            // Sync formatted value to the view model
                            viewModel.listingPrice = "$\(priceDigits).00"
                        }
                    ))
                    .id("priceField")
                    .focused($priceFieldFocused)
                    .submitLabel(.done)
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(activeColor)
                    .frame(minWidth: 24)

                    Text(".00")
                        .foregroundColor(activeColor)
                }
                .padding(12)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
                }
                
                // Submit Button
                Button(action: {
                    guard !isSubmitting else { return }
                    // Dismiss keyboard before submission
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

                    // Ensure listingPrice is synced to formatted value
                    viewModel.listingPrice = "$\(priceDigits).00"

                    viewModel.category = fields.selectedCategory
                    viewModel.subcategory = fields.selectedSubcategory
                    viewModel.size = fields.selectedSize
                    viewModel.condition = fields.selectedCondition
                    viewModel.gender = fields.selectedGender
                    viewModel.color = fields.selectedColors.prefix(2).joined(separator: ", ")
                    if viewModel.validate() {
                        isSubmitting = true
                        Task {
                            let listing = viewModel.toSingleListing()
                            // Dismiss immediately; let the submission finish in the background
                            dismiss()
                            await ListingSubmission.shared.submit(listing: listing, patternJPEGData: patternJPEGData)
                            isSubmitting = false
                        }
                    } else {
                        viewModel.showValidationAlert = true
                    }
                }) {
                    Text("Submit Listing")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)
                .alert(isPresented: $viewModel.showValidationAlert) {
                    Alert(title: Text("Validation"),
                          message: Text(viewModel.validationMessage),
                          dismissButton: .default(Text("OK")))
                }
                }
                .padding(.bottom, max(0, keyboardHeight - 8))
                .padding()
                .contentShape(Rectangle())
                .onTapGesture { endEditing() }
            }
            // Keep this on the ScrollViewReader so we can react to focus changes
            .onChange(of: priceFieldFocused) { focused in
                if focused {
                    withAnimation {
                        proxy.scrollTo("priceField", anchor: .center)
                    }
                } else {
                    // If user leaves the field empty, restore to "0"
                    if priceDigits.isEmpty {
                        priceDigits = "0"
                    }
                    // Sync formatted value on blur
                    viewModel.listingPrice = "$\(priceDigits).00"
                }
            }
        }
        .navigationTitle("Add Single Listing")
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            viewModel.brand = selectedBrand
            // Sync selections with any pre-existing viewModel values
            if !viewModel.size.isEmpty { fields.selectedSize = viewModel.size }
            if !viewModel.condition.isEmpty { fields.selectedCondition = viewModel.condition }
            if !viewModel.gender.isEmpty { fields.selectedGender = viewModel.gender }
            if !viewModel.color.isEmpty {
                let parts: [String] = viewModel.color
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                fields.selectedColors = Array(parts.prefix(2))
            }
            // Initialize priceDigits from any existing formatted value; default to "0"
            if !viewModel.listingPrice.isEmpty {
                let digits = viewModel.listingPrice.filter { $0.isNumber }
                if digits.isEmpty || digits.allSatisfy({ $0 == "0" }) {
                    priceDigits = "0"
                } else {
                    priceDigits = String(digits.drop(while: { $0 == "0" }))
                }
            } else {
                priceDigits = "0"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = frame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .onChange(of: fields.selectedCategory) { _ in
            if !currentSizeOptions.contains(fields.selectedSize) {
                fields.selectedSize = ""
            }
        }
        .onChange(of: fields.selectedSubcategory) { _ in
            if !currentSizeOptions.contains(fields.selectedSize) {
                fields.selectedSize = ""
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    priceFieldFocused = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

private struct ThumbnailView: View {
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
                            if let prepared = ui.preparingThumbnail(of: target) { // fast path
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

private struct SelectionSheet: View {
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

private struct ColorSelectionSheet: View {
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
