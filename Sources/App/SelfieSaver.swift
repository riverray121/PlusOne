import Photos

// Writes passing unlock selfies to the photo library. Access is add-only,
// which never exposes existing photos to the app; the price is that photos
// land in the library with no PlusOne album, since albums need read access.
enum SelfieSaver {
    // Prompts on first use, then reports the standing decision.
    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async { completion(status == .authorized) }
        }
    }

    static func save(_ jpeg: Data) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: jpeg, options: nil)
            }
        }
    }
}
