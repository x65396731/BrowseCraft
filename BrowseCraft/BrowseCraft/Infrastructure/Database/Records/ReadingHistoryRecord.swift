import Foundation
import GRDB

struct ReadingHistoryRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "readingHistory"

    var itemId: String
    var chapterId: String?
    var pageIndex: Int
    var updatedAt: Date

    init(history: ReadingHistory) {
        self.itemId = history.itemId
        self.chapterId = history.chapterId
        self.pageIndex = history.pageIndex
        self.updatedAt = history.updatedAt
    }

    func domainModel() -> ReadingHistory {
        return ReadingHistory(
            itemId: self.itemId,
            chapterId: self.chapterId,
            pageIndex: self.pageIndex,
            updatedAt: self.updatedAt
        )
    }
}

