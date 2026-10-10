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

    /// 中文注释：当前来源读过的全部书，最近的在前（库页瓷砖与行的「读到哪」）。
    func fetchHistory(userID: String, sourceID: String) throws -> [BookReadingHistory] {
        return try self.database.queue.read { database in
            let records: [BookReadingHistoryRecord] = try BookReadingHistoryRecord
                .filter(BookReadingHistoryRecord.Columns.userID == userID)
                .filter(BookReadingHistoryRecord.Columns.sourceID == sourceID)
                .order(BookReadingHistoryRecord.Columns.visitedAt.desc)
                .fetchAll(database)

            return records.map { record in
                return record.domainModel()
            }
        }
    }

    /// 中文注释：某一本书的那一条（站点书详情的续读章），不再读全表再在内存里找。
    func fetchHistory(userID: String, sourceID: String, bookItemID: String) throws -> BookReadingHistory? {
        return try self.database.queue.read { database in
            let record: BookReadingHistoryRecord? = try BookReadingHistoryRecord
                .filter(BookReadingHistoryRecord.Columns.userID == userID)
                .filter(BookReadingHistoryRecord.Columns.sourceID == sourceID)
                .filter(BookReadingHistoryRecord.Columns.bookItemID == bookItemID)
                .order(BookReadingHistoryRecord.Columns.visitedAt.desc)
                .fetchOne(database)

            return record?.domainModel()
        }
    }

    func delete(_ history: BookReadingHistory) throws {
        try self.delete([history])
    }

    /// 中文注释：批量删除在一个写事务里完成，不再每条一个事务。
    func delete(_ histories: [BookReadingHistory]) throws {
        guard histories.isEmpty == false else {
            return
        }
        try self.database.queue.write { database in
            for history: BookReadingHistory in histories {
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
}
