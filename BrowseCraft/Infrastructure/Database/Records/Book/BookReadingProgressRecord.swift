import Foundation
@preconcurrency import GRDB

// 中文注释：BookReadingProgressRecord 是 book_reading_progress 表的一行，主键 (bookID, userID)。

struct BookReadingProgressRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "book_reading_progress"

    var bookID: String
    var userID: String
    var locatorJSON: String
    var totalProgression: Double?
    var updatedAt: Date

    enum Columns {
        static let bookID: Column = Column("bookID")
        static let userID: Column = Column("userID")
    }

    init(progress: BookReadingProgress) {
        self.bookID = progress.bookID.uuidString
        self.userID = progress.userID
        self.locatorJSON = progress.locatorJSON
        self.totalProgression = progress.totalProgression
        self.updatedAt = progress.updatedAt
    }

    func domainModel() -> BookReadingProgress? {
        guard let bookID: UUID = UUID(uuidString: self.bookID) else {
            return nil
        }
        return BookReadingProgress(
            bookID: bookID,
            userID: self.userID,
            locatorJSON: self.locatorJSON,
            totalProgression: self.totalProgression,
            updatedAt: self.updatedAt
        )
    }
}
