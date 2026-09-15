import BrowseCraftDomain
import Foundation
import GRDB

// 中文注释：BookReadingHistoryRecord 是 book_reading_history 表的一行，主键 (userID, sourceID, detailURL)。

struct BookReadingHistoryRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "book_reading_history"

    var userID: String
    var sourceID: String
    var detailURL: String
    var bookItemID: String
    var bookTitle: String
    var coverURL: String?
    var chapterTitle: String?
    var chapterURL: String?
    var visitedAt: Date
    var sourceSnapshotJSON: String?

    enum Columns {
        static let userID: Column = Column("userID")
        static let sourceID: Column = Column("sourceID")
        static let detailURL: Column = Column("detailURL")
        static let visitedAt: Column = Column("visitedAt")
    }

    init(history: BookReadingHistory) {
        self.userID = history.userID
        self.sourceID = history.sourceID
        self.detailURL = history.detailURL
        self.bookItemID = history.bookItemID
        self.bookTitle = history.bookTitle
        self.coverURL = history.coverURL?.absoluteString
        self.chapterTitle = history.chapterTitle
        self.chapterURL = history.chapterURL?.absoluteString
        self.visitedAt = history.visitedAt
        self.sourceSnapshotJSON = Self.encodeSourceSnapshot(history.sourceSnapshot)
    }

    func domainModel() -> BookReadingHistory {
        return BookReadingHistory(
            userID: self.userID,
            sourceID: self.sourceID,
            detailURL: self.detailURL,
            bookItemID: self.bookItemID,
            bookTitle: self.bookTitle,
            coverURL: self.coverURL.flatMap(URL.init(string:)),
            chapterTitle: self.chapterTitle,
            chapterURL: self.chapterURL.flatMap(URL.init(string:)),
            visitedAt: self.visitedAt,
            sourceSnapshot: Self.decodeSourceSnapshot(self.sourceSnapshotJSON)
        )
    }

    private static func encodeSourceSnapshot(_ snapshot: SourceSnapshot?) -> String? {
        guard let snapshot: SourceSnapshot = snapshot,
              let data: Data = try? JSONEncoder().encode(snapshot) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static func decodeSourceSnapshot(_ json: String?) -> SourceSnapshot? {
        guard let json: String = json,
              let data: Data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(SourceSnapshot.self, from: data)
    }
}
