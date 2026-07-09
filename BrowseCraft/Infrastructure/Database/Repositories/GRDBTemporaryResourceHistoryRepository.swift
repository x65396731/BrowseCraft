import Foundation
import GRDB

// 中文注释：GRDBTemporaryResourceHistoryRepository 只保存未绑定 Source 的临时访问历史。
final class GRDBTemporaryResourceHistoryRepository: TemporaryResourceHistoryRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func save(_ history: TemporaryResourceHistory) throws {
        let record: TemporaryResourceHistoryRecord = TemporaryResourceHistoryRecord(history: history)

        try self.database.queue.write { database in
            try Self.upsert(record, in: database)
        }
    }

    func fetchHistory(userID: String) throws -> [TemporaryResourceHistory] {
        return try self.database.queue.read { database in
            let records: [TemporaryResourceHistoryRecord] = try TemporaryResourceHistoryRecord
                .filter(Column("userID") == userID)
                .order(Column("visitedAt").desc)
                .fetchAll(database)

            return records.compactMap { record in
                return record.domainModel()
            }
        }
    }

    func delete(_ history: TemporaryResourceHistory) throws {
        try self.database.queue.write { database in
            try database.execute(
                sql: """
                DELETE FROM \(TemporaryResourceHistoryRecord.databaseTableName)
                WHERE userID = ? AND kind = ? AND resourceURL = ?
                """,
                arguments: [
                    history.userID,
                    history.kind.rawValue,
                    history.resourceURL.absoluteString
                ]
            )
        }
    }

    private static func upsert(_ record: TemporaryResourceHistoryRecord, in database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO \(TemporaryResourceHistoryRecord.databaseTableName)
                (userID, kind, title, resourceURL, coverURL, sourcePageURL, matchedKeyword, videoPlaybackKind, visitedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(userID, kind, resourceURL) DO UPDATE SET
                title = excluded.title,
                coverURL = excluded.coverURL,
                sourcePageURL = excluded.sourcePageURL,
                matchedKeyword = excluded.matchedKeyword,
                videoPlaybackKind = excluded.videoPlaybackKind,
                visitedAt = excluded.visitedAt
            """,
            arguments: [
                record.userID,
                record.kind,
                record.title,
                record.resourceURL,
                record.coverURL,
                record.sourcePageURL,
                record.matchedKeyword,
                record.videoPlaybackKind,
                record.visitedAt
            ]
        )
    }
}
