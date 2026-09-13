import Foundation

// 中文注释：BookFileInspecting 只嗅探文件形态，不打开出版物；Infrastructure 用 Readium 的格式嗅探实现。

enum LocalBookFileInspection: Equatable, Sendable {
    case supported(LocalBookFormat, fileExtension: String)
    case unsupported
}

protocol BookFileInspecting: Sendable {
    func inspect(fileURL: URL) async throws -> LocalBookFileInspection
}
