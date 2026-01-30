//
//  ProfileAvatarView.swift
//  Exchange
//
//  Reusable avatar view with consistent loading states and accessibility.
//

import SwiftUI

struct ProfileAvatarView: View {
    let fileURL: URL?
    let remoteURLString: String?
    let size: CGFloat
    let borderColor: Color
    let borderWidth: CGFloat

    init(
        fileURL: URL? = nil,
        remoteURLString: String? = nil,
        size: CGFloat = 110,
        borderColor: Color = .white,
        borderWidth: CGFloat = 3
    ) {
        self.fileURL = fileURL
        self.remoteURLString = remoteURLString
        self.size = size
        self.borderColor = borderColor
        self.borderWidth = borderWidth
    }

    var body: some View {
        ZStack {
            avatarImage
            Circle()
                .stroke(borderColor, lineWidth: borderWidth)
                .frame(width: size, height: size)
        }
        .accessibilityLabel("Profile photo")
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let fileURL = fileURL {
            AsyncImage(url: fileURL) { phase in
                avatarPhaseContent(phase)
            }
        } else if let urlString = remoteURLString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                avatarPhaseContent(phase)
            }
        } else {
            placeholderImage
        }
    }

    @ViewBuilder
    private func avatarPhaseContent(_ phase: AsyncImagePhase) -> some View {
        switch phase {
        case .empty:
            ProgressView()
                .frame(width: size, height: size)
        case .success(let image):
            image
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        case .failure:
            placeholderImage
        @unknown default:
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .foregroundStyle(.secondary)
    }
}

// MARK: - Preview
#if DEBUG
struct ProfileAvatarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ProfileAvatarView()
            ProfileAvatarView(size: 60, borderColor: .blue)
        }
        .padding()
        .previewDisplayName("Profile Avatars")
    }
}
#endif
