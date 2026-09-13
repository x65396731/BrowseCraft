import Foundation
import ReadiumShared
import ReadiumStreamer
import UIKit

// 中文注释：ReadiumBookPublicationOpener 打开容器内的书；句柄里包着 Readium `Publication`，Features 建 Navigator 时取用。

final class ReadiumBookPublicationHandle: BookPublicationHandle, @unchecked Sendable {
    let publication: Publication
    let metadata: BookPublicationMetadata

    init(publication: Publication, metadata: BookPublicationMetadata) {
        self.publication = publication
        self.metadata = metadata
    }
}

final class ReadiumBookPublicationOpener: BookPublicationOpening, @unchecked Sendable {
    private let environment: ReadiumBookEnvironment

    init(environment: ReadiumBookEnvironment = .shared) {
        self.environment = environment
    }

    func openPublication(fileURL: URL, format: LocalBookFormat) async throws -> BookPublicationHandle {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw BookPublicationOpenError.fileMissing
        }
        guard let readiumURL: FileURL = FileURL(url: fileURL) else {
            throw BookPublicationOpenError.fileMissing
        }
        let fileExtension: String = fileURL.pathExtension.lowercased()
        let hints: FormatHints = FormatHints(
            fileExtension: fileExtension.isEmpty ? nil : FileExtension(rawValue: fileExtension)
        )

        let asset: Asset
        switch await self.environment.assetRetriever.retrieve(url: readiumURL, hints: hints) {
        case .success(let retrieved):
            asset = retrieved
        case .failure(.formatNotSupported):
            throw BookPublicationOpenError.unsupportedFormat
        case .failure(let error):
            throw BookPublicationOpenError.parsingFailed(reason: Self.reason(for: error))
        }
        guard ReadiumBookEnvironment.localBookFormat(for: asset.format) == format else {
            throw BookPublicationOpenError.unsupportedFormat
        }

        let publication: Publication
        switch await self.environment.publicationOpener.open(asset: asset, allowUserInteraction: false) {
        case .success(let opened):
            publication = opened
        case .failure(let error):
            throw BookPublicationOpenError.parsingFailed(reason: Self.reason(for: error))
        }

        let isRestricted: Bool = publication.isRestricted
        var coverImageData: Data? = nil
        if isRestricted == false, case .success(let image?) = await publication.cover() {
            coverImageData = image.pngData()
        }
        let metadata: BookPublicationMetadata = BookPublicationMetadata(
            title: publication.metadata.title,
            author: publication.metadata.authors.first?.name,
            coverImageData: coverImageData,
            isRestricted: isRestricted
        )
        return ReadiumBookPublicationHandle(publication: publication, metadata: metadata)
    }

    /// 中文注释：错误只保留类型名，不带路径与出版物内容。
    private static func reason(for error: Error) -> String {
        return String(describing: type(of: error)) + "." + String(describing: error).split(separator: "(").first.map(String.init).unsafelyUnwrapped
    }
}
