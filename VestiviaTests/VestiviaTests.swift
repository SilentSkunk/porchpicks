//
//  VestiviaTests.swift
//  VestiviaTests
//
//  Created by William Hunsucker on 7/16/25.
//

import Testing
@testable import Vestivia

// MARK: - Input Sanitization Tests
struct InputSanitizationTests {

    @Test func sanitizeRemovesDangerousCharacters() {
        let input = "<script>alert('xss')</script>"
        let result = AppConstants.InputSanitization.sanitize(input)
        #expect(!result.contains("<"))
        #expect(!result.contains(">"))
        #expect(!result.contains("'"))
    }

    @Test func sanitizeTrimsWhitespace() {
        let input = "   hello world   "
        let result = AppConstants.InputSanitization.sanitize(input)
        #expect(result == "hello world")
    }

    @Test func sanitizeRespectsMaxLength() {
        let input = String(repeating: "a", count: 2000)
        let result = AppConstants.InputSanitization.sanitize(input)
        #expect(result.count == AppConstants.InputSanitization.maxTextFieldLength)
    }

    @Test func sanitizeTitleRemovesNewlines() {
        let input = "Title with\nnewline"
        let result = AppConstants.InputSanitization.sanitizeTitle(input)
        #expect(!result.contains("\n"))
        #expect(result.contains(" "))
    }

    @Test func sanitizeUsernameOnlyAllowsAlphanumericAndUnderscore() {
        let input = "User@Name#123!"
        let result = AppConstants.InputSanitization.sanitizeUsername(input)
        #expect(result == "username123")
    }

    @Test func sanitizeUsernameIsLowercased() {
        let input = "UserName"
        let result = AppConstants.InputSanitization.sanitizeUsername(input)
        #expect(result == "username")
    }

    @Test func sanitizeUsernameRespectsMaxLength() {
        let input = String(repeating: "a", count: 50)
        let result = AppConstants.InputSanitization.sanitizeUsername(input)
        #expect(result.count == AppConstants.InputSanitization.maxUsernameLength)
    }

    @Test func isValidPriceFormatAcceptsValidPrices() {
        #expect(AppConstants.InputSanitization.isValidPriceFormat("$123.45"))
        #expect(AppConstants.InputSanitization.isValidPriceFormat("123.45"))
        #expect(AppConstants.InputSanitization.isValidPriceFormat("$1,234.56"))
        #expect(AppConstants.InputSanitization.isValidPriceFormat("0.99"))
    }

    @Test func isValidPriceFormatRejectsInvalidPrices() {
        #expect(!AppConstants.InputSanitization.isValidPriceFormat("abc"))
        #expect(!AppConstants.InputSanitization.isValidPriceFormat("$abc"))
        #expect(!AppConstants.InputSanitization.isValidPriceFormat(""))
    }
}

// MARK: - App Constants Tests
struct AppConstantsTests {

    @Test func deepLinksGenerateValidURLs() {
        let listingId = "test-listing-123"

        let deepLink = AppConstants.DeepLinks.listingURL(for: listingId)
        #expect(deepLink != nil)
        #expect(deepLink?.scheme == AppConstants.DeepLinks.scheme)

        let webURL = AppConstants.DeepLinks.webListingURL(for: listingId)
        #expect(webURL.absoluteString.contains(listingId))
    }

    @Test func imageCompressionQualitiesAreValid() {
        #expect(AppConstants.ImageCompression.standardQuality > 0)
        #expect(AppConstants.ImageCompression.standardQuality <= 1)
        #expect(AppConstants.ImageCompression.thumbnailQuality > 0)
        #expect(AppConstants.ImageCompression.thumbnailQuality <= 1)
    }

    @Test func listingConstantsAreReasonable() {
        #expect(AppConstants.Listing.maxDescriptionLength == 1000)
        #expect(AppConstants.Listing.maxPriceCents == 100_000_00)
        #expect(AppConstants.Listing.minRequiredImages >= 1)
        #expect(AppConstants.Listing.maxImages >= AppConstants.Listing.minRequiredImages)
    }

    @Test func networkingConstantsAreReasonable() {
        #expect(AppConstants.Networking.defaultTimeout > 0)
        #expect(AppConstants.Networking.uploadRetryAttempts >= 1)
        #expect(AppConstants.Networking.retryBaseDelay > 0)
    }
}

// MARK: - ListingViewModel Tests
struct ListingViewModelTests {

    @Test func validationFailsWithEmptyBrand() async {
        let viewModel = await MainActor.run { ListingViewModel() }
        await MainActor.run {
            viewModel.brand = ""
            viewModel.category = "Clothing"
            viewModel.listingPrice = "$50.00"
            // Note: selectedImages would need a UIImage which we can't easily create in tests
        }
        let isValid = await MainActor.run { viewModel.validate() }
        #expect(!isValid)
        let message = await MainActor.run { viewModel.validationMessage }
        #expect(message.contains("Brand"))
    }

    @Test func validationFailsWithEmptyCategory() async {
        let viewModel = await MainActor.run { ListingViewModel() }
        await MainActor.run {
            viewModel.brand = "Nike"
            viewModel.category = ""
            viewModel.listingPrice = "$50.00"
        }
        let isValid = await MainActor.run { viewModel.validate() }
        #expect(!isValid)
        let message = await MainActor.run { viewModel.validationMessage }
        #expect(message.contains("Category"))
    }

    @Test func validationFailsWithEmptyPrice() async {
        let viewModel = await MainActor.run { ListingViewModel() }
        await MainActor.run {
            viewModel.brand = "Nike"
            viewModel.category = "Clothing"
            viewModel.listingPrice = ""
        }
        let isValid = await MainActor.run { viewModel.validate() }
        #expect(!isValid)
        let message = await MainActor.run { viewModel.validationMessage }
        #expect(message.contains("Price"))
    }

    @Test func validationFailsWithZeroPrice() async {
        let viewModel = await MainActor.run { ListingViewModel() }
        await MainActor.run {
            viewModel.brand = "Nike"
            viewModel.category = "Clothing"
            viewModel.listingPrice = "$0.00"
        }
        let isValid = await MainActor.run { viewModel.validate() }
        #expect(!isValid)
        let message = await MainActor.run { viewModel.validationMessage }
        #expect(message.contains("greater than $0"))
    }

    @Test func validationFailsWithExcessivePrice() async {
        let viewModel = await MainActor.run { ListingViewModel() }
        await MainActor.run {
            viewModel.brand = "Nike"
            viewModel.category = "Clothing"
            viewModel.listingPrice = "$999999.00"
        }
        let isValid = await MainActor.run { viewModel.validate() }
        #expect(!isValid)
        let message = await MainActor.run { viewModel.validationMessage }
        #expect(message.contains("100,000"))
    }

    @Test func validationFailsWithTooLongDescription() async {
        let viewModel = await MainActor.run { ListingViewModel() }
        await MainActor.run {
            viewModel.brand = "Nike"
            viewModel.category = "Clothing"
            viewModel.listingPrice = "$50.00"
            viewModel.description = String(repeating: "a", count: 1500)
        }
        let isValid = await MainActor.run { viewModel.validate() }
        #expect(!isValid)
        let message = await MainActor.run { viewModel.validationMessage }
        #expect(message.contains("1000"))
    }
}

// MARK: - SellerProfile Tests
struct SellerProfileTests {

    @Test func fromDictParsesUsername() {
        let dict: [String: Any] = [
            "username": "TestUser",
            "usernameLower": "testuser",
            "rating": 4.5
        ]
        let profile = SellerProfile.from(dict: dict, uid: "test-uid")
        #expect(profile.username == "TestUser")
        #expect(profile.id == "test-uid")
    }

    @Test func fromDictFallsBackToUsernameLower() {
        let dict: [String: Any] = [
            "usernameLower": "testuser",
            "rating": 4.5
        ]
        let profile = SellerProfile.from(dict: dict, uid: "test-uid")
        #expect(profile.username == "testuser")
    }

    @Test func fromDictHandlesMissingUsername() {
        let dict: [String: Any] = [
            "rating": 4.5
        ]
        let profile = SellerProfile.from(dict: dict, uid: "test-uid")
        #expect(profile.username == "User")
    }

    @Test func fromDictParsesRating() {
        let dict: [String: Any] = [
            "username": "Test",
            "rating": NSNumber(value: 4.5)
        ]
        let profile = SellerProfile.from(dict: dict, uid: "test-uid")
        #expect(profile.rating == 4.5)
    }

    @Test func fromDictHandlesMissingRating() {
        let dict: [String: Any] = [
            "username": "Test"
        ]
        let profile = SellerProfile.from(dict: dict, uid: "test-uid")
        #expect(profile.rating == 0)
    }

    @Test func fromDictParsesProfileImageURL() {
        let dict: [String: Any] = [
            "username": "Test",
            "profileImageURL": "https://example.com/image.jpg"
        ]
        let profile = SellerProfile.from(dict: dict, uid: "test-uid")
        #expect(profile.profileImageURL == "https://example.com/image.jpg")
    }

    @Test func fromDictFallsBackToAlternativeImageFields() {
        // Test profilePhotoURL fallback
        let dict1: [String: Any] = [
            "username": "Test",
            "profilePhotoURL": "https://example.com/photo.jpg"
        ]
        let profile1 = SellerProfile.from(dict: dict1, uid: "test-uid")
        #expect(profile1.profileImageURL == "https://example.com/photo.jpg")

        // Test photoURL fallback
        let dict2: [String: Any] = [
            "username": "Test",
            "photoURL": "https://example.com/photo2.jpg"
        ]
        let profile2 = SellerProfile.from(dict: dict2, uid: "test-uid")
        #expect(profile2.profileImageURL == "https://example.com/photo2.jpg")

        // Test avatarURL fallback
        let dict3: [String: Any] = [
            "username": "Test",
            "avatarURL": "https://example.com/avatar.jpg"
        ]
        let profile3 = SellerProfile.from(dict: dict3, uid: "test-uid")
        #expect(profile3.profileImageURL == "https://example.com/avatar.jpg")
    }
}

// MARK: - SingleListing Tests
struct SingleListingTests {

    @Test func initializesWithCorrectValues() {
        let listing = SingleListing(
            category: "Clothing",
            subcategory: "Tops",
            size: "M",
            condition: "New",
            gender: "Unisex",
            description: "Test description",
            color: "Blue",
            originalPrice: "$100.00",
            listingPrice: "$50.00",
            brand: "Nike"
        )

        #expect(listing.category == "Clothing")
        #expect(listing.subcategory == "Tops")
        #expect(listing.size == "M")
        #expect(listing.condition == "New")
        #expect(listing.gender == "Unisex")
        #expect(listing.description == "Test description")
        #expect(listing.color == "Blue")
        #expect(listing.originalPrice == "$100.00")
        #expect(listing.listingPrice == "$50.00")
        #expect(listing.brand == "Nike")
    }

    @Test func hasUniqueId() {
        let listing1 = SingleListing(
            category: "A", subcategory: "", size: "", condition: "",
            gender: "", description: "", color: "", originalPrice: "",
            listingPrice: "", brand: ""
        )
        let listing2 = SingleListing(
            category: "B", subcategory: "", size: "", condition: "",
            gender: "", description: "", color: "", originalPrice: "",
            listingPrice: "", brand: ""
        )
        #expect(listing1.id != listing2.id)
    }
}
