//
//  CategoryPickerView.swift
//  Exchange
//
//  Created by William Hunsucker on 7/22/25.
//


import SwiftUI

struct Category {
    let name: String
    let subcategories: [String]
}

let allCategories: [Category] = [
    Category(name: "Accessories", subcategories: [
        "Bags",
        "Belts",
        "Bibs",
        "Diaper Covers",
        "Face Masks",
        "Hair Accessories",
        "Hats",
        "Jewelry",
        "Mittens",
        "Socks & Tights",
        "Sunglasses",
        "Suspenders",
        "Ties",
        "Underwear",
        "Watches"
    ]),
    Category(name: "Bottoms", subcategories: [
        "Casual",
        "Formal",
        "Jeans",
        "Jumpsuits & Rompers",
        "Leggings",
        "Overalls",
        "Shorts",
        "Skirts",
        "Skorts",
        "Sweatpants & Joggers"
    ]),
    Category(name: "Dresses", subcategories: [
        "Casual",
        "Formal"
    ]),
    Category(name: "Jackets & Coats", subcategories: [
        "Blazers",
        "Capes",
        "Jean Jackets",
        "Pea Coats",
        "Puffers",
        "Raincoats",
        "Vests"
    ]),
    Category(name: "One Pieces", subcategories: [
        "Bodysuits",
        "Footies"
    ]),
    Category(name: "Pajamas", subcategories: [
        "Nightgowns",
        "Pajama Bottoms",
        "Pajama Sets",
        "Pajama Tops",
        "Robes",
        "Sleep Sacks"
    ]),
    Category(name: "Shirts & Tops", subcategories: [
        "Blouses",
        "Button Down Shirts",
        "Camisoles",
        "Jerseys",
        "Polos",
        "Sweaters",
        "Sweatshirts & Hoodies",
        "Tank Tops",
        "Tees - Long Sleeve",
        "Tees - Short Sleeve"
    ]),
    Category(name: "Shoes", subcategories: [
        "Baby & Walker",
        "Boots",
        "Dress Shoes",
        "Moccasins",
        "Rain & Snow Boots",
        "Sandals & Flip Flops",
        "Slippers",
        "Sneakers",
        "Water Shoes"
    ])
]

struct CategoryPickerView: View {
    @Binding var isPresented: Bool
    @Binding var selectedCategory: String
    @Binding var selectedSubcategory: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Categories")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                ForEach(allCategories, id: \.name) { category in
                    NavigationLink(destination:
                        SubcategoryPickerView(
                            category: category.name,
                            subcategories: category.subcategories,
                            selectedCategory: $selectedCategory,
                            selectedSubcategory: $selectedSubcategory,
                            isPresented: $isPresented
                        )
                    ) {
                        HStack {
                            Text(category.name)
                                .bodyStyle()
                            if selectedCategory == category.name {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .foregroundColor(.purple)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

struct SubcategoryPickerView: View {
    let category: String
    let subcategories: [String]
    @Binding var selectedCategory: String
    @Binding var selectedSubcategory: String
    @Binding var isPresented: Bool

    var body: some View {
        List(subcategories, id: \.self) { subcategory in
            Button(action: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    selectedCategory = category
                    selectedSubcategory = subcategory
                    isPresented = false
                }
            }) {
                HStack {
                    Text(subcategory)
                        .bodyStyle()
                    if selectedSubcategory == subcategory {
                        Spacer()
                        Image(systemName: "checkmark")
                            .foregroundColor(.purple)
                    }
                }
            }
        }
        .navigationTitle(category)
        .navigationBarTitleDisplayMode(.inline)
    }
}
