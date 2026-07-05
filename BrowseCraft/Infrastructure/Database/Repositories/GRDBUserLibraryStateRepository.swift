import Foundation
import GRDB

// 中文注释：GRDBUserLibraryStateRepository 通过 SQLite 保存用户 Library 启动状态。

/// 中文注释：每个 userID 只有一条当前 Library 状态，保存时使用 upsert。
final class GRDBUserLibraryStateRepository: UserLibraryStateRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func fetch(userID: String) throws -> UserLibraryState? {
        return try self.database.queue.read { database in
            let record: UserLibraryStateRecord? = try UserLibraryStateRecord
                .filter(Column("userID") == userID)
                .fetchOne(database)

            return record?.domainModel()
        }
    }

    func save(_ state: UserLibraryState) throws {
        let record: UserLibraryStateRecord = try UserLibraryStateRecord(state: state)

        try self.database.queue.write { database in
            try Self.upsert(record, in: database)
        }
    }

    private static func upsert(_ record: UserLibraryStateRecord, in database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO \(UserLibraryStateRecord.databaseTableName)
                (userID, selectedSourceID, listContextJSON, lastRefreshAt, updatedAt)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(userID) DO UPDATE SET
                selectedSourceID = excluded.selectedSourceID,
                listContextJSON = excluded.listContextJSON,
                lastRefreshAt = excluded.lastRefreshAt,
                updatedAt = excluded.updatedAt
            """,
            arguments: [
                record.userID,
                record.selectedSourceID,
                record.listContextJSON,
                record.lastRefreshAt,
                record.updatedAt
            ]
        )
    }
}
