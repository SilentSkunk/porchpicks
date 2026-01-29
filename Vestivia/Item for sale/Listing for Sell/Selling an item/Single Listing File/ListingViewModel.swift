import SwiftUI

class ListingViewModel: ObservableObject {
    @Published var brand: String = ""
    @Published var category: String = ""
    @Published var subcategory: String = ""
    @Published var size: String = ""
    @Published var condition: String = ""
    @Published var gender: String = ""
    @Published var color: String = ""
    @Published var originalPrice: String = ""
    @Published var listingPrice: String = ""
    @Published var description: String = ""
    
    // Store selected UIImages for the UI
    @Published var selectedImages: [UIImage] = []
    
    // Computed property for image data
    var selectedImagesData: [Data] {
        selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
    }
    
    // Validation
    @Published var showValidationAlert: Bool = false
    var validationMessage: String = ""

    // Validation constants
    private static let maxDescriptionLength = 1000
    private static let maxPriceCents = 100_000_00 // $100,000.00 max

    func validate() -> Bool {
        var errors: [String] = []

        // Required fields
        if brand.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Brand is required")
        }
        if category.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Category is required")
        }
        if selectedImages.isEmpty {
            errors.append("At least one image is required")
        }

        // Price validation
        if listingPrice.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Price is required")
        } else {
            // Parse price - expects format like "$123.00"
            let priceStr = listingPrice
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespaces)

            if let priceValue = Double(priceStr) {
                if priceValue <= 0 {
                    errors.append("Price must be greater than $0")
                } else if priceValue > Double(Self.maxPriceCents) / 100 {
                    errors.append("Price cannot exceed $100,000")
                }
            } else {
                errors.append("Invalid price format")
            }
        }

        // Description length validation
        if description.count > Self.maxDescriptionLength {
            errors.append("Description cannot exceed \(Self.maxDescriptionLength) characters")
        }

        // Set validation message
        if errors.isEmpty {
            validationMessage = ""
            return true
        } else {
            validationMessage = errors.joined(separator: "\n")
            return false
        }
    }
    
    func addImage(_ image: UIImage) {
        selectedImages.append(image)
    }
    
    /// Synchronous version - use only when you don't care about main thread blocking.
    func toSingleListing() -> SingleListing {
        return SingleListing(
            category: category,
            subcategory: subcategory,
            size: size,
            condition: condition,
            gender: gender,
            description: description,
            color: color,
            originalPrice: originalPrice,
            listingPrice: listingPrice,
            brand: brand,
            images: selectedImages
        )
    }

    /// Async version - use from UI code to prevent main thread blocking during image compression.
    func toSingleListingAsync() async -> SingleListing {
        return await SingleListing.create(
            category: category,
            subcategory: subcategory,
            size: size,
            condition: condition,
            gender: gender,
            description: description,
            color: color,
            originalPrice: originalPrice,
            listingPrice: listingPrice,
            brand: brand,
            images: selectedImages
        )
    }
}
