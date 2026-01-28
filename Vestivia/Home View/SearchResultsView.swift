import SwiftUI
import Foundation

enum SearchResultType {
    case brand
    case seller
    case item
}

struct SearchResultsView: View {
    var query: String
    var results: [CombinedSearchResult]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Results for \(query)")
                .headerStyle()
                .padding()

            if results.isEmpty {
                Text("No results found.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                List(results) { result in
                    let item = result.item
                    NavigationLink(destination: destinationView(for: result)) {
                        HStack {
                            if let img = item.searchImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(8)
                            } else {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(8)
                            }

                            VStack(alignment: .leading) {
                                Text(item.searchTitle).bold()
                                if let subtitle = item.searchSubtitle {
                                    Text(subtitle).bodyStyle()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Search Results")
        .navigationBarBackButtonHidden(false)
    }

    @ViewBuilder
    private func destinationView(for result: CombinedSearchResult) -> some View {
        switch result.searchType {
        case .brand:
            if let brand = BrandData.allBrands.first(where: { $0.name == result.item.searchTitle }) {
                BrandSearchResultsView(brand: brand)
            } else {
                EmptyView()
            }
        case .seller:
            Text("Seller profile view coming soon.")
        case .item:
            Text("Item details view coming soon.")
        }
    }
}
