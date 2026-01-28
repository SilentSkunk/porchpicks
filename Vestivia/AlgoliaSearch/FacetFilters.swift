//
//  FacetFilters.swift
//  Exchange
//
//  Created by William Hunsucker on 8/21/25.
//


// FacetFilters.swift
import Foundation
import InstantSearch
import InstantSearchSwiftUI
import AlgoliaSearchClient

/// Central place for predefined (fixed) facet lists.
/// It connects lists <-> FilterState and exposes SwiftUI controllers for rendering.
final class FacetFilters {

    // MARK: - Group names (must match how you group in FilterState)
    static let brandGroup      = "brand"
    static let categoryGroup   = "category"
    static let sizeGroup       = "size"
    static let colorGroup      = "color"
    static let conditionGroup  = "condition"

    // MARK: - Canonical facet values (replace with your own)
    struct Values {
        static var brand: [String] {
            // Map Brand objects to their name property
            return BrandFields().brands.map { $0.name }
        }
        static let category = ["Tops", "Bottoms", "Dresses", "Outerwear", "Shoes", "Accessories"]
        static let size = ["NB","0-3M","3-6M","6-9M","12-18M","2T","3T","4T","5","6","7","8","10","12"]
        static let color = ["Pink","Blue","White","Navy","Green","Red","Yellow","Neutral"]
        static let condition = ["New With Tags","Like New","Gently Used","Play Condition"]
    }

    // MARK: - SwiftUI controllers (bind these to your views)
    let brandController      = FilterListObservableController<Filter.Facet>()
    let categoryController   = FilterListObservableController<Filter.Facet>()
    let sizeController       = FilterListObservableController<Filter.Facet>()
    let colorController      = FilterListObservableController<Filter.Facet>()
    let conditionController  = FilterListObservableController<Filter.Facet>()

    private let filterState: FilterState

    // MARK: - Keep connectors alive
    private var brandConnector: FacetFilterListConnector?
    private var categoryConnector: FacetFilterListConnector?
    private var sizeConnector: FacetFilterListConnector?
    private var colorConnector: FacetFilterListConnector?
    private var conditionConnector: FacetFilterListConnector?

    // MARK: - Init
    init(filterState: FilterState) {
        self.filterState = filterState

        brandConnector = FacetFilterListConnector(
            facetFilters: Values.brand.map { Filter.Facet(attribute: "brand", stringValue: $0) },
            selectionMode: .single,                // single-select brand
            filterState: filterState,
            operator: .and,                        // AND across attributes
            groupName: Self.brandGroup,
            controller: brandController
        )

        categoryConnector = FacetFilterListConnector(
            facetFilters: Values.category.map { Filter.Facet(attribute: "category", stringValue: $0) },
            selectionMode: .single,
            filterState: filterState,
            operator: .and,
            groupName: Self.categoryGroup,
            controller: categoryController
        )

        sizeConnector = FacetFilterListConnector(
            facetFilters: Values.size.map { Filter.Facet(attribute: "size", stringValue: $0) },
            selectionMode: .multiple,              // often multi-select
            filterState: filterState,
            operator: .and,
            groupName: Self.sizeGroup,
            controller: sizeController
        )

        colorConnector = FacetFilterListConnector(
            facetFilters: Values.color.map { Filter.Facet(attribute: "color", stringValue: $0) },
            selectionMode: .multiple,
            filterState: filterState,
            operator: .and,
            groupName: Self.colorGroup,
            controller: colorController
        )

        conditionConnector = FacetFilterListConnector(
            facetFilters: Values.condition.map { Filter.Facet(attribute: "condition", stringValue: $0) },
            selectionMode: .single,
            filterState: filterState,
            operator: .and,
            groupName: Self.conditionGroup,
            controller: conditionController
        )
    }

    // Clear all facet selections
    func clearAll() {
        filterState[and: Self.brandGroup].removeAll()
        filterState[and: Self.categoryGroup].removeAll()
        filterState[and: Self.sizeGroup].removeAll()
        filterState[and: Self.colorGroup].removeAll()
        filterState[and: Self.conditionGroup].removeAll()
        filterState.notifyChange()
    }

    // MARK: - Programmatic selection helpers
    func selectBrand(_ value: String?) { setSingle(attribute: "brand", group: Self.brandGroup, value: value) }
    func selectCategory(_ value: String?) { setSingle(attribute: "category", group: Self.categoryGroup, value: value) }
    func setSizes(_ values: [String]) { setMultiple(attribute: "size", group: Self.sizeGroup, values: values) }
    func setColors(_ values: [String]) { setMultiple(attribute: "color", group: Self.colorGroup, values: values) }
    func selectCondition(_ value: String?) { setSingle(attribute: "condition", group: Self.conditionGroup, value: value) }

    // MARK: - Internal helpers
    private func normalized(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        if v.compare("all", options: .caseInsensitive) == .orderedSame { return nil }
        return v
    }

    private func setSingle(attribute: Attribute, group: String, value: String?) {
        let accessor = filterState[and: group]
        accessor.removeAll()
        if let v = normalized(value) {
            accessor.add(Filter.Facet(attribute: attribute, stringValue: v))
        }
        filterState.notifyChange()
    }

    private func setMultiple(attribute: Attribute, group: String, values: [String]) {
        let accessor = filterState[and: group]
        accessor.removeAll()
        let filters = values.compactMap { v -> Filter.Facet? in
            guard let nv = normalized(v) else { return nil }
            return Filter.Facet(attribute: attribute, stringValue: nv)
        }
        filters.forEach { accessor.add($0) }
        filterState.notifyChange()
    }
}

extension FacetFilters {
    /// Order‑insensitive signature of the current active facet selections.
    /// This is used for caching search results per filter combination.
    func currentSignature() -> String {
        func sig<S: Sequence>(_ items: S) -> String where S.Element == Filter.Facet {
            items.map { $0.description }.sorted().joined(separator: ",")
        }

        let brandSig     = sig(brandController.selections)
        let categorySig  = sig(categoryController.selections)
        let sizeSig      = sig(sizeController.selections)
        let colorSig     = sig(colorController.selections)
        let conditionSig = sig(conditionController.selections)

        // Group parts by facet group names to avoid collisions
        let parts: [String] = [
            "brand=[\(brandSig)]",
            "category=[\(categorySig)]",
            "size=[\(sizeSig)]",
            "color=[\(colorSig)]",
            "condition=[\(conditionSig)]"
        ]
        return parts.joined(separator: "|")
    }
}
