import SwiftUI
import PhotosUI

struct ImagePicker: View {
    @Environment(\.dismiss) private var dismiss
    var onImagesPicked: ([UIImage]) -> Void
    var onCancel: (() -> Void)? = nil  // <-- New callback

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var capturedImages: [UIImage] = []
    
    var body: some View {
        VStack(spacing: 20) {
            // Camera Button
            Button(action: {
                showCamera = true
            }) {
                Text("Take Photo")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            
            // Gallery Picker
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 10,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Text("Select Images from Gallery")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            // Cancel Button
            Button(action: {
                onCancel?()
                dismiss()
            }) {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
        .onChange(of: selectedItems) { _, newItems in
            Task {
                var images: [UIImage] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        images.append(image)
                    }
                }
                onImagesPicked(images)
                dismiss()
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView { image in
                if let image = image {
                    capturedImages.append(image)
                    onImagesPicked([image])
                } else {
                    onCancel?()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Camera Integration
struct CameraView: UIViewControllerRepresentable {
    var completion: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            parent.completion(image)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.completion(nil)
        }
    }
}
