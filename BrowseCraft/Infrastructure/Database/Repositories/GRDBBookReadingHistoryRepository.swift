import Foundation
import GRDB

// 中文注释：GRDBBookReadingHistoryRepository 通过 SQLite 保存站点书阅读历史。

/// 中文注释：保存时按 userID/sourceID/detailURL upsert，同一本书只留一条、访问时间与章节随最近一次阅读更新。
final class GRDBBookReadingHistoryRepository: BookReadingHistoryRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func save(_ history: BookReadingHistory) throws {
        var record: BookReadingHistoryRecord = BookReadingHistoryRecord(history: history)

        try self.database.queue.write { database in
            try record.save(database)
        }
    }

    func fetchHistory(userID: String) throws -> [BookReadingHistory] {
        return try self.database.queue.read { database in
            let records: [BookReadingHistoryRecord] = try BookReadingHistoryRecord
                .filter(BookReadingHistoryRecord.Columns.userID == userID)
                .order(BookReadingHistoryRecord.Columns.visitedAt.desc)
                .fetchAll(database)

            return records.map { record in
                return record.domainModel()
            }
        }
    }

    func delete(_ history: BookReadingHistory) throws {
        try self.database.queue.write { database in
            try database.execute(
                sql: """
                DELETE FROM \(BookReadingHistoryRecord.databaseTableName)
                WHERE userID = ? AND sourceID = ? AND detailURL = ?
                """,
                arguments: [
                    history.userID,
                    history.sourceID,
                    history.detailURL
                ]
            )
        }
    }
}
