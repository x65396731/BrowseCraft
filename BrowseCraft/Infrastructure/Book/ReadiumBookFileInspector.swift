import Foundation
import ReadiumShared

// 中文注释：ReadiumBookFileInspector 用 Readium 的格式嗅探判断一个文件是 EPUB、音频书还是不支持；不解析出版物。

final class ReadiumBookFileInspector: BookFileInspecting, @unchecked Sendable {
    private let environment: ReadiumBookEnvironment

    init(environment: ReadiumBookEnvironment = .shared) {
        self.environment = environment
    }

    func inspect(fileURL: URL) async throws -> LocalBookFileInspection {
        guard let readiumURL: FileURL = FileURL(url: fileURL) else {
            return .unsupported
        }
        let fileExtension: String = fileURL.pathExtension.lowercased()
        let hints: FormatHints = FormatHints(
            fileExtension: fileExtension.isEmpty ? nil : FileExtension(rawValue: fileExtension)
        )
        let accessing: Bool = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        switch await self.environment.assetRetriever.sniffFormat(of: readiumURL, hints: hints) {
        case .success(let format):
            guard let localFormat: LocalBookFormat = ReadiumBookEnvironment.localBookFormat(for: format) else {
                return .unsupported
            }
            // 中文注释：原文件有扩展名就照抄（m4a / m4b 不改成 Readium 的规范名 mp4），没有才用嗅探到的规范扩展名。
            let resolvedExtension: String = fileExtension.isEmpty
                ? (format.fileExtension?.rawValue ?? "bin")
                : fileExtension
            return .supported(localFormat, fileExtension: resolvedExtension)
        case .failure(.formatNotSupported):
            return .unsupported
        case .failure(let error):
            throw error
        }
    }
}
