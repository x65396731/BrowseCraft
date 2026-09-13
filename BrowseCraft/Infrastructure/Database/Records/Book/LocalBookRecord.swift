import Foundation
@preconcurrency import GRDB

// 中文注释：LocalBookRecord 是 local_books 表的一行；UUID 以 uuidString 存 TEXT。

struct LocalBookRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "local_books"

    var id: String
    var userID: String
    var title: String
    var author: String?
    var format: String
    var fileRelativePath: String
    var coverRelativePath: String?
    var fileSHA256: String
    var byteCount: Int
    var importedAt: Date
    var lastOpenedAt: Date?

    enum Columns {
        static let id: Column = Column("id")
        static let userID: Column = Column("userID")
        static let fileSHA256: Column = Column("fileSHA256")
        static let importedAt: Column = Column("importedAt")
    }

    init(book: LocalBook) {
        self.id = book.id.uuidString
        self.userID = book.userID
        self.title = book.title
        self.author = book.author
        self.format = book.format.rawValue
        self.fileRelativePath = book.fileRelativePath
        self.coverRelativePath = book.coverRelativePath
        self.fileSHA256 = book.fileSHA256
        self.byteCount = book.byteCount
        self.importedAt = book.importedAt
        self.lastOpenedAt = book.lastOpenedAt
    }

    /// 中文注释：格式列出现未知值（比未来版本写入的）时整行丢弃，不猜。
    func domainModel() -> LocalBook? {
        guard let id: UUID = UUID(uuidString: self.id), let format: LocalBookFormat = LocalBookFormat(rawValue: self.format) else {
            return nil
        }
        return LocalBook(
            id: id,
            userID: self.userID,
            title: self.title,
            author: self.author,
            format: format,
            fileRelativePath: self.fileRelativePath,
            coverRelativePath: self.coverRelativePath,
            fileSHA256: self.fileSHA256,
            byteCount: self.byteCount,
            importedAt: self.importedAt,
            lastOpenedAt: self.lastOpenedAt
        )
    }
}
