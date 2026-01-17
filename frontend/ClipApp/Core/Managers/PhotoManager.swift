import Photos
import UIKit
import Combine

@MainActor
final class PhotoManager: ObservableObject {
    @Published private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
    }

    func fetchAsset(for localIdentifier: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return result.firstObject
    }

    func fetchThumbnail(for asset: PHAsset, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func saveVideo(from url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var placeholder: PHObjectPlaceholder?

            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: url, options: nil)
                placeholder = request.placeholderForCreatedAsset
            } completionHandler: { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let localIdentifier = placeholder?.localIdentifier {
                    continuation.resume(returning: localIdentifier)
                } else {
                    continuation.resume(throwing: PhotoManagerError.saveFailed)
                }
            }
        }
    }
}

enum PhotoManagerError: Error {
    case saveFailed
    case assetNotFound
}
