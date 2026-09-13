import Foundation

// 中文注释：BookPublicationOpening 打开容器内的书，返回不透明句柄；Infrastructure 里句柄包着 Readium `Publication`，
// Features 拿句柄去建 Navigator。Application 只看元数据与「是否受限」。

struct BookPublicationMetadata: Equatable, Sendable {
    var title: String?
    var author: String?
    var coverImageData: Data?
    /// 中文注释：LCP 等内容保护下的出版物打不开正文，导入时直接拒绝。
    var isRestricted: Bool
}

/// 中文注释：不透明句柄。Application 不定义任何方法，避免把 Readium 类型漏进来。
protocol BookPublicationHandle: AnyObject, Sendable {
    var metadata: BookPublicationMetadata { get }
}

enum BookPublicationOpenError: Error, Equatable, Sendable {
    case fileMissing
    case unsupportedFormat
    case protectedPublication
    case parsingFailed(reason: String)
}

protocol BookPublicationOpening: Sendable {
    func openPublication(fileURL: URL, format: LocalBookFormat) async throws -> BookPublicationHandle
}
