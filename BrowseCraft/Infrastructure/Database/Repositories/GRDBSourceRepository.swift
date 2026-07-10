import Foundation
import GRDB

// 中文注释：GRDBSourceRepository 通过 SQLite 保存、读取和删除 Source。

/// 中文注释：Source 删除采用应用级级联规则，避免留下无法恢复的 history/library state。
final class GRDBSourceRepository: SourceRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func fetchSources() throws -> [Source] {
        return try self.database.queue.read { database in
            let records: [SourceRecord] = try SourceRecord
                .filter(SourceRecord.Columns.userID == AppUser.localDefaultID)
                .filter(SourceRecord.Columns.deletedAt == nil)
                .order(SourceRecord.Columns.updatedAt.desc)
                .fetchAll(database)

            return try records.map { record in
                return try record.domainModel()
            }
        }
    }

    func saveSource(_ source: Source) throws {
        try self.database.queue.write { database in
            var record: SourceRecord = try SourceRecord(source: source)
            try record.save(database)

            if source.isBuiltIn == false {
                try SyncQueueRecord.enqueue(
                    entityType: .source,
                    entityID: source.id,
                    operation: .upsert,
                    updatedAt: source.updatedAt,
                    in: database
                )
            }
        }
    }

    func deleteSource(id: String) throws {
        try self.database.queue.write { database in
            let now: Date = Date()
            try Self.clearSourceSelection(sourceID: id, in: database)

            if var record: SourceRecord = try SourceRecord.fetchOne(database, key: id) {
                record.updatedAt = now
                record.deletedAt = now
                try record.save(database)
            }

            if id.hasPrefix("built-in.") == false {
                try SyncQueueRecord.enqueue(
                    entityType: .source,
                    entityID: id,
                    operation: .delete,
                    updatedAt: now,
                    in: database
                )
            }
        }
    }

    /// 中文注释：Source 只拥有 Library 当前选择状态；历史和收藏都依靠快照独立于来源生命周期。
    private static func clearSourceSelection(sourceID: String, in database: Database) throws {
        try database.execute(
            sql: """
            UPDATE \(UserLibraryStateRecord.databaseTableName)
            SET selectedSourceID = NULL,
                listContextJSON = NULL,
                lastRefreshAt = NULL,
                updatedAt = ?
            WHERE selectedSourceID = ?
            """,
            arguments: [
                Date(),
                sourceID
            ]
        )
    }
}
