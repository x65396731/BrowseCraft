import Foundation
import GRDB

// 中文注释：GRDBRSSReadingHistoryRepository 通过 SQLite 保存 RSS 详情访问历史。

/// 中文注释：保存时按 userID/sourceID/itemID upsert，读取时只返回指定用户的历史。
final class GRDBRSSReadingHistoryRepository: RSSReadingHistoryRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func save(_ history: RSSReadingHistory) throws {
        let record: RSSReadingHistoryRecord = RSSReadingHistoryRecord(history: history)

        try self.database.queue.write { database in
            try Self.upsert(record, in: database)
        }
    }

    func fetchHistory(userID: String) throws -> [RSSReadingHistory] {
        return try self.database.queue.read { database in
            let records: [RSSReadingHistoryRecord] = try RSSReadingHistoryRecord
                .filter(Column("userID") == userID)
                .order(Column("visitedAt").desc)
                .fetchAll(database)

            return records.map { record in
                return record.domainModel()
            }
        }
    }

    func delete(_ history: RSSReadingHistory) throws {
        let record: RSSReadingHistoryRecord = RSSReadingHistoryRecord(history: history)

        try self.database.queue.write { database in
            try database.execute(
                sql: """
                DELETE FROM \(RSSReadingHistoryRecord.databaseTableName)
                WHERE userID = ? AND sourceID = ? AND itemID = ?
                """,
                arguments: [
                    record.userID,
                    record.sourceID,
                    record.itemID
                ]
            )
        }
    }

    private static func upsert(_ record: RSSReadingHistoryRecord, in database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO \(RSSReadingHistoryRecord.databaseTableName)
                (userID, sourceID, itemID, dataType, title, dataContent, dataTime, visitedAt, detailURL, sourceName, originFeedURL, sourceSnapshotJSON)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(userID, sourceID, itemID) DO UPDATE SET
                dataType = excluded.dataType,
                title = excluded.title,
                dataContent = excluded.dataContent,
                dataTime = excluded.dataTime,
                visitedAt = excluded.visitedAt,
                detailURL = excluded.detailURL,
                sourceName = excluded.sourceName,
                originFeedURL = excluded.originFeedURL,
                sourceSnapshotJSON = excluded.sourceSnapshotJSON
            """,
            arguments: [
                record.userID,
                record.sourceID,
                record.itemID,
                record.dataType,
                record.title,
                record.dataContent,
                record.dataTime,
                record.visitedAt,
                record.detailURL,
                record.sourceName,
                record.originFeedURL,
                record.sourceSnapshotJSON
            ]
        )
    }
}
