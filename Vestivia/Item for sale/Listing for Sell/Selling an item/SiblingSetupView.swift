//
//  SiblingSetupView.swift
//  Vestivia
//
//  Created by William Hunsucker on 7/17/25.
//

import SwiftUI
import PhotosUI
/// NOTE: Navigation is controlled solely by `navigateNext`. Avoid calling `onNext` here; run any side-effects from the destination instead if truly necessary.

struct SiblingSetupView: View {
    @Binding var numberOfSets: Int
    @Binding var brand: String
    @Binding var showingBrandPicker: Bool
    @Binding var showingValidation: Bool
    @Binding var validationMessage: String
    let onNext: (_ isSingleListing: Bool) -> Void

    @State private var isSingleListing = true
    @State private var navigateNext = false
    // Pattern capture state (kept local; NOT uploaded here)
    @State private var hasKnownPattern = false
    @State private var showPatternSheet = false
    @State private var showPatternTips = false
    @State private var patternPreview: UIImage? = nil
    @State private var patternJPEGData: Data? = nil
    private let brands = BrandFields().brands // ✅ Use instance property for brand list

var body: some View {
    ScrollView {
        VStack(spacing: 28) {
            headerSection
            listingTypeSection
            if !isSingleListing { siblingStepperSection }
            brandPickerSection
            patternSection
            nextButton
        }
        .padding(.bottom, 40)
    }
    .navigationTitle("Create Listing")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(isPresented: $navigateNext) {
        destinationView
    }
    .sheet(isPresented: $showPatternTips) {
        // Supply your asset names. Add images to Assets.xcassets with these names (or change them here).
        PatternTipsSheet(
            badAssetName: "pattern_bad",
            goodAssetName: "pattern_good"
        ) {
            // User acknowledged the tips — proceed to capture
            showPatternTips = false
            showPatternSheet = true
        }
    }
    .onChange(of: hasKnownPattern) { _, newValue in
        if newValue {
            showPatternTips = true
        } else {
            patternPreview = nil
            patternJPEGData = nil
        }
    }
}
// MARK: - Components

    @ViewBuilder
    private var destinationView: some View {
        if isSingleListing {
            AddListingViewSingle(selectedBrand: brand, patternJPEGData: patternJPEGData)
        } else {
            Text("Sibling Listing View coming soon")
                .font(.title)
                .foregroundColor(.gray)
        }
    }

    private var headerSection: some View {
        Text("Create Listing")
            .font(.largeTitle).bold()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.horizontal)
    }

    private var listingTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Listing Type")
                .font(.headline)
            Picker("Listing Type", selection: $isSingleListing) {
                Text("Single Item").tag(true)
                Text("Sibling Set").tag(false)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private var siblingStepperSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How many sets are you listing?")
                .font(.headline)
            Stepper(value: $numberOfSets, in: 1...10) {
                Text("\(numberOfSets) set\(numberOfSets > 1 ? "s" : "")")
            }
            .padding(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private var brandPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Brand")
                .font(.headline)

            Picker(selection: $brand, label: Text(brand.isEmpty ? "Select Brand" : brand)) {
                // Placeholder matches initial state so Picker has a valid tag for ""
                Text("Select Brand").tag("")

                ForEach(brands, id: \.name) { brandObject in
                    Text(brandObject.name).tag(brandObject.name)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private var patternSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $hasKnownPattern.animation()) {
                Text("This listing has a known pattern")
                    .font(.headline)
            }
            .padding(.trailing)

            if hasKnownPattern {
                Text("If you know the outfit’s pattern, add a quick photo so we can help buyers searching for this pattern. Try to center the motif, similar to the Pattern Match prompt.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    ZStack {
                        if let img = patternPreview {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipped()
                                .cornerRadius(8)
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                                .frame(width: 72, height: 72)
                                .overlay(
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .imageScale(.large)
                                        .foregroundColor(.secondary)
                                )
                        }
                    }

                    Button {
                        showPatternSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: patternPreview == nil ? "camera" : "arrow.triangle.2.circlepath.camera")
                            Text(patternPreview == nil ? "Add Pattern Photo" : "Retake Pattern Photo")
                        }
                    }

                    if patternPreview != nil {
                        Button(role: .destructive) {
                            patternPreview = nil
                            patternJPEGData = nil
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .sheet(isPresented: $showPatternSheet) {
            PatternCaptureSheet { image in
                // Compress to ~512px square JPEG (no upload here)
                let target: CGFloat = 512
                let squared = image.squareScaled(to: target)
                self.patternPreview = squared
                self.patternJPEGData = squared.jpegData(compressionQuality: 0.85)
            }
        }
    }

    private var nextButton: some View {
        Button(action: {
            // ✅ Validate brand before navigating
            if brand.isEmpty {
                validationMessage = "Please select a brand."
                showingValidation = true
                return
            }
            // Navigate first to avoid intermediate pops caused by parent side-effects
            DispatchQueue.main.async {
                navigateNext = true
                print("[SiblingSetup] Navigating to AddListingViewSingle with brand=\(brand)")
            }
        }) {
            Text("Next")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .padding(.horizontal)
        }
        .padding(.top, 12)
    }
}

// MARK: - Pattern Tips (interstitial)
struct PatternTipsSheet: View {
    /// Optional asset names for the example images. Provide via init or leave nil to use placeholders.
    var badAssetName: String? = nil
    var goodAssetName: String? = nil
    var onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("How to take the best pattern photo")
                        .font(.title2).bold()

                    Text("Center the fabric, fill the frame, avoid glare. See examples below.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                exampleImageView(assetName: badAssetName)
                                    .frame(height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.title)
                                    .padding(8)
                            }
                            Text("Too far / angled / glare")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                exampleImageView(assetName: goodAssetName)
                                    .frame(height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title)
                                    .padding(8)
                            }
                            Text("Centered / close / no glare")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Fill the frame with the pattern", systemImage: "viewfinder")
                        Label("Hold the phone parallel to the fabric", systemImage: "rectangle.and.hand.point.up.left.filled")
                        Label("Avoid glare and harsh shadows", systemImage: "sun.max")
                        Label("Use soft light (window or shade)", systemImage: "lightbulb")
                    }
                    .font(.body)

                    Button {
                        onContinue()
                    } label: {
                        Text("I understand — Continue")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.top, 6)
                }
                .padding()
            }
            .navigationTitle("Pattern Tips")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Renders an example image if the asset exists; otherwise shows a gray placeholder.
    @ViewBuilder
    private func exampleImageView(assetName: String?) -> some View {
        if let name = assetName, let ui = UIImage(named: name) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .background(Color(.systemGray5))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        }
    }
}

// MARK: - Pattern capture (Camera / Library)

struct PatternCaptureSheet: UIViewControllerRepresentable {
    var onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onPicked: (UIImage) -> Void
        init(onPicked: @escaping (UIImage) -> Void) { self.onPicked = onPicked }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let edited = info[.editedImage] as? UIImage
            let original = info[.originalImage] as? UIImage
            if let img = edited ?? original {
                onPicked(img)
            }
            picker.presentingViewController?.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.presentingViewController?.dismiss(animated: true)
        }
    }
}

// MARK: - UIImage helpers
private extension UIImage {
    func squareScaled(to target: CGFloat) -> UIImage {
        let minSide = min(size.width, size.height)
        let cropRect = CGRect(
            x: (size.width - minSide) / 2,
            y: (size.height - minSide) / 2,
            width: minSide, height: minSide
        ).integral

        guard let cgImage = self.cgImage?.cropping(to: cropRect) else { return self }
        let square = UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format)
        return renderer.image { _ in
            square.draw(in: CGRect(x: 0, y: 0, width: target, height: target))
        }
    }
}
