//
//  PhotoEditView.swift
//  Vestivia
//

import SwiftUI

struct PhotoEditView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let onComplete: (UIImage) -> Void

    @State private var rotationAngle: CGFloat = 0
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    @State private var imageFrame: CGRect = .zero

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                GeometryReader { geo in
                    VStack {
                        Spacer().frame(height: geo.size.height * 0.05)
                        ZStack {
                            Image(uiImage: rotatedImage())
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .scaleEffect(scale)
                                .offset(x: offset.width + dragOffset.width,
                                        y: offset.height + dragOffset.height)
                                .gesture(
                                    DragGesture().updating($dragOffset) { value, state, _ in
                                        state = value.translation
                                    }
                                    .onEnded { value in
                                        offset.width += value.translation.width
                                        offset.height += value.translation.height
                                    }
                                )
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { newScale in
                                            scale = newScale
                                        }
                                )
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear
                                            .onAppear {
                                                DispatchQueue.main.async {
                                                    imageFrame = proxy.frame(in: .global)
                                                }
                                            }
                                    }
                                )

                            cropOverlay(in: geo.size)
                        }
                        Spacer()
                    }
                }

                VStack {
                    Spacer()
                    HStack(spacing: 20) {
                        Button(action: {
                            withAnimation {
                                rotationAngle += 90
                            }
                        }) {
                            Image(systemName: "rotate.right")
                            Text("Rotate")
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(10)


                        Button(action: {
                            let cropped = cropImage()
                            onComplete(cropped)
                            dismiss()
                        }) {
                            Image(systemName: "checkmark")
                            Text("Done")
                        }
                        .padding()
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(10)
                    }
                    .foregroundColor(.white)
                    .padding()
                }
            }
            .navigationTitle("Edit Photo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func rotatedImage() -> UIImage {
        guard image.cgImage != nil else { return image }
        let radians = rotationAngle * .pi / 180
        let newSize = CGRect(origin: .zero, size: image.size)
            .applying(CGAffineTransform(rotationAngle: radians)).integral.size

        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        if let context = UIGraphicsGetCurrentContext() {
            context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            context.rotate(by: radians)
            image.draw(in: CGRect(
                x: -image.size.width / 2,
                y: -image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            ))
            let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return rotatedImage ?? image
        }
        return image
    }

    private func cropOverlay(in size: CGSize) -> some View {
        let width = size.width * 0.9
        let height = width

        return ZStack {
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: width, height: height)
                .position(x: size.width / 2, y: size.height / 2)
            Path { path in
                let step: CGFloat = 3
                for i in 1..<Int(step) {
                    let dx = width * CGFloat(i) / step
                    path.move(to: CGPoint(x: size.width/2 - width/2 + dx, y: size.height/2 - height/2))
                    path.addLine(to: CGPoint(x: size.width/2 - width/2 + dx, y: size.height/2 + height/2))
                }
                for j in 1..<Int(step) {
                    let dy = height * CGFloat(j) / step
                    path.move(to: CGPoint(x: size.width/2 - width/2, y: size.height/2 - height/2 + dy))
                    path.addLine(to: CGPoint(x: size.width/2 + width/2, y: size.height/2 - height/2 + dy))
                }
            }
            .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    private func cropImage() -> UIImage {
        let rotated = rotatedImage()
        let imageSize = rotated.size

        let cropBoxSize = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.9
        let cropBoxOrigin = CGPoint(
            x: (UIScreen.main.bounds.width - cropBoxSize) / 2,
            y: (UIScreen.main.bounds.height - cropBoxSize) / 2
        )
        let cropBox = CGRect(origin: cropBoxOrigin, size: CGSize(width: cropBoxSize, height: cropBoxSize))

        let scaleX = imageSize.width / imageFrame.width
        let scaleY = imageSize.height / imageFrame.height

        let relativeX = (cropBox.minX - imageFrame.minX) * scaleX
        let relativeY = (cropBox.minY - imageFrame.minY) * scaleY
        let relativeWidth = cropBox.width * scaleX
        let relativeHeight = cropBox.height * scaleY

        let cropRect = CGRect(x: relativeX, y: relativeY, width: relativeWidth, height: relativeHeight)

        guard let cgImage = rotated.cgImage?.cropping(to: cropRect.integral) else {
            return rotated
        }

        return UIImage(cgImage: cgImage, scale: rotated.scale, orientation: rotated.imageOrientation)
    }
}

struct PhotoEditView_Previews: PreviewProvider {
    static var previews: some View {
        PhotoEditView(image: UIImage(systemName: "photo")!) { _ in }
    }
}
