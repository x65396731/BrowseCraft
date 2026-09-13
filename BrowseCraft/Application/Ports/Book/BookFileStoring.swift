import Foundation

// 中文注释：BookFileStoring 把外部文件复制进 App 容器的书籍目录并管理它们；
// 安全作用域访问、iCloud 按需下载都在 Infrastructure 实现里处理，Application 只拿相对路径。

struct StoredBookFile: Equatable, Sendable {
    let relativePath: String
    let sha256: String
    let byteCount: Int
}

protocol BookFileStoring: Sendable {
    /// 中文注释：复制 `sourceURL` 到容器内，文件名由 `bookID` 与扩展名决定；返回相对路径、内容哈希与字节数。
    func storeBookFile(from sourceURL: URL, bookID: UUID, fileExtension: String) async throws -> StoredBookFile
    /// 中文注释：封面另存一份图片文件；返回相对路径。
    func storeCover(_ data: Data, bookID: UUID) async throws -> String
    /// 中文注释：删除相对路径指向的文件；文件不存在不算错误。
    func removeFile(relativePath: String) async throws
    func fileURL(relativePath: String) -> URL
}
