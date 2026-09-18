import Foundation

// 中文注释：LocalBook 是用户从「文件」导入的一本本地书（EPUB 或音频书）。
// 它不是 Source，不进 SourceConfiguration，也不参与 CloudKit 同步（首批，见 docs/design/Local-Book-Import-Design.md）。

/// 中文注释：首批只接两种文件形态；PDF、CBZ、LCP 加密 EPUB 都不在范围内。
enum LocalBookFormat: String, Codable, CaseIterable, Hashable, Sendable {
    /// EPUB 文件，走 EPUB Navigator。
    case epub
    /// 单个音频文件（mp3 / m4a / m4b）或 zip / zab 音频包，走 Audio Navigator。
    case audiobook
}

struct LocalBook: Identifiable, Hashable, Sendable {
    var id: UUID
    var userID: String
    var title: String
    var author: String?
    var format: LocalBookFormat
    /// 中文注释：相对 App 容器书籍目录的路径，文件已复制进容器；绝对路径由文件存储端口解析。
    var fileRelativePath: String
    var coverRelativePath: String?
    /// 中文注释：导入时算的内容哈希，同一文件再次导入时用它去重。
    var fileSHA256: String
    var byteCount: Int
    var importedAt: Date
    var lastOpenedAt: Date?
}
