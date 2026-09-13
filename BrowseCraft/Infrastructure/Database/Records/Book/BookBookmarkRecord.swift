import Foundation
@preconcurrency import GRDB

// 中文注释：BookBookmarkRecord 是 book_bookmarks 表的一行。

struct BookBookmarkRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "book_bookmarks"

    var id: String
    var bookID: String
    var userID: String
    var locatorJSON: String
    var title: String?
    var snippet: String?
    var createdAt: Date

    enum Columns {
        static let id: Column = Column("id")
        static let bookID: Column = Column("bookID")
        static let userID: Column = Column("userID")
        static let createdAt: Column = Column("createdAt")
    }

    init(bookmark: BookBookmark) {
        self.id = bookmark.id.uuidString
        self.bookID = bookmark.bookID.uuidString
        self.userID = bookmark.userID
        self.locatorJSON = bookmark.locatorJSON
        self.title = bookmark.title
        self.snippet = bookmark.snippet
        self.createdAt = bookmark.createdAt
    }

    func domainModel() -> BookBookmark? {
        guard let id: UUID = UUID(uuidString: self.id), let bookID: UUID = UUID(uuidString: self.bookID) else {
            return nil
        }
        return BookBookmark(
            id: id,
            bookID: bookID,
            userID: self.userID,
            locatorJSON: self.locatorJSON,
            title: self.title,
            snippet: self.snippet,
            createdAt: self.createdAt
        )
    }
}
