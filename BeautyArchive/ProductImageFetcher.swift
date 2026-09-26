import Foundation
import LinkPresentation
import OSLog
import SwiftData
import UniformTypeIdentifiers

enum ProductImageFetcher {
    enum FetchError: LocalizedError {
        case unsupportedImage
        case imageTooLarge

        var errorDescription: String? {
            switch self {
            case .unsupportedImage: "画像を読み込めませんでした。"
            case .imageTooLarge: "画像のサイズが大きすぎます。"
            }
        }
    }

    @MainActor
    static func fetch(from url: URL) async throws -> Data? {
        let metadataProvider = LPMetadataProvider()
        metadataProvider.timeout = 8
        let metadata = try await metadataProvider.startFetchingMetadata(for: url)
        guard let imageProvider = metadata.imageProvider else { return nil }
        guard let imageType = imageProvider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .image) == true
        }) else { throw FetchError.unsupportedImage }

        let original: Data = try await withCheckedThrowingContinuation { continuation in
            imageProvider.loadDataRepresentation(forTypeIdentifier: imageType) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? FetchError.unsupportedImage)
                }
            }
        }
        guard original.count <= 15_000_000 else { throw FetchError.imageTooLarge }
        guard let optimized = await Task.detached(priority: .utility, operation: {
            PhotoImageProcessor.optimizedJPEG(original)
        }).value else { throw FetchError.unsupportedImage }
        return optimized
    }
}

@MainActor
enum ProductImageAutoLoader {
    private static let logger = Logger(
        subsystem: "com.takuyaokuda.BeautyArchive", category: "ProductImageAutoLoader"
    )

    static func schedule(
        productID: UUID, url: URL, sourceURL: String,
        savedAt: Date, container: ModelContainer
    ) {
        Task {
            do {
                guard let image = try await ProductImageFetcher.fetch(from: url) else { return }
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<BeautyProduct>(
                    predicate: #Predicate { $0.id == productID }
                )
                guard let product = try context.fetch(descriptor).first,
                      product.imageData.isEmpty,
                      product.purchaseURL == sourceURL,
                      product.updatedAt == savedAt else { return }
                product.imageData = image
                product.updatedAt = .now
                try context.save()
            } catch {
                logger.info("Automatic product image retrieval failed: \(error.localizedDescription)")
            }
        }
    }
}
