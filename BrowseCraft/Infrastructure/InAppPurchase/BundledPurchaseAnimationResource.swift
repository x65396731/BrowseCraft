import Foundation

struct BundledPurchaseAnimationResource {
    enum ResourceError: LocalizedError {
        case missingResource(fileName: String)

        var errorDescription: String? {
            switch self {
            case .missingResource(let fileName):
                return "The bundled purchase animation resource \(fileName) could not be found."
            }
        }
    }

    private enum Asset {
        case video
        case poster

        var name: String {
            return "purchase-background"
        }

        var fileExtension: String {
            switch self {
            case .video:
                return "mp4"
            case .poster:
                return "jpg"
            }
        }

        var fileName: String {
            return "\(self.name).\(self.fileExtension)"
        }
    }

    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func videoURL() throws -> URL {
        return try self.url(for: .video)
    }

    func posterURL() throws -> URL {
        return try self.url(for: .poster)
    }

    private func url(for asset: Asset) throws -> URL {
        if let url: URL = self.bundle.url(
            forResource: asset.name,
            withExtension: asset.fileExtension
        ) {
            return url
        }

        // Xcode normally flattens these resources into the bundle root. Keep the
        // source-directory lookup as a fallback for alternate bundle packaging.
        if let url: URL = self.bundle.url(
            forResource: asset.name,
            withExtension: asset.fileExtension,
            subdirectory: "InAppPurchase"
        ) {
            return url
        }

        throw ResourceError.missingResource(fileName: asset.fileName)
    }
}
