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
    
    func validate() -> Bool {
        !brand.isEmpty && !category.isEmpty && !listingPrice.isEmpty
    }
    
    func addImage(_ image: UIImage) {
        selectedImages.append(image)
    }
    
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
            images: selectedImages // ✅ Pass UIImages directly
        )
    }
}
