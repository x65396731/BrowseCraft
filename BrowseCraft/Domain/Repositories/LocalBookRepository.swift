import Foundation

// 中文注释：LocalBookRepository 负责本地书清单的读写；文件本身由 Application 层的文件存储端口管理。
protocol LocalBookRepository: Sendable {
    func fetchBooks(userID: String) throws -> [LocalBook]
    func fetchBook(id: UUID, userID: String) throws -> LocalBook?
    /// 中文注释：按内容哈希找已导入的同一文件，导入用例用它去重。
    func fetchBook(fileSHA256: String, userID: String) throws -> LocalBook?
    func saveBook(_ book: LocalBook) throws
    /// 中文注释：删除书；进度与书签由数据库外键级联删除。
    func deleteBook(id: UUID, userID: String) throws
}
