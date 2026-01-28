import SwiftUI
import Foundation

struct BrandGridView: View {
    let brands: [Brand]
    @Environment(\.presentationMode) var presentationMode
    @State private var searchText = ""

    var filteredBrands: [Brand] {
        if searchText.isEmpty {
            return brands
        } else {
            return brands.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
            VStack(spacing: 0) {
                // Search bar with back button
                HStack(spacing: 8) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.blue)
                    }

                    TextField("Search brands", text: $searchText)
                        .padding(10)
                        .background(Color(.systemGray5))
                        .cornerRadius(10)
                }
            }
            .navigationBarBackButtonHidden(true)
        }
    }


// TabIcon view for bottom tab bar
struct TabIcon: View {
    let name: String
    let label: String
    var badge: Bool = false
    var badgeCount: Int? = nil

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: name)
                    .font(.title2)
                if let count = badgeCount {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 10, y: -10)
                } else if badge {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .offset(x: 6, y: -6)
                }
            }
            Text(label)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .foregroundColor(.black)
    }
}
