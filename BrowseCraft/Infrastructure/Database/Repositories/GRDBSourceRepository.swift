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
                .order(Column("updatedAt").desc)
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
        }
    }

    func deleteSource(id: String) throws {
        try self.database.queue.write { database in
            try Self.deleteSourceCascade(sourceID: id, in: database)
            _ = try SourceRecord.deleteOne(database, key: id)
        }
    }

    /// 中文注释：Source 是 RSS/漫画/视频历史和 Library 当前状态的 owner；收藏规则尚未设计，暂不触碰 favorites。
    private static func deleteSourceCascade(sourceID: String, in database: Database) throws {
        try database.execute(
            sql: """
            DELETE FROM \(RSSReadingHistoryRecord.databaseTableName)
            WHERE sourceID = ?
            """,
            arguments: [sourceID]
        )
        try database.execute(
            sql: """
            DELETE FROM \(ComicChapterHistoryRecord.databaseTableName)
            WHERE sourceID = ?
            """,
            arguments: [sourceID]
        )
        try database.execute(
            sql: """
            DELETE FROM \(VideoWatchHistoryRecord.databaseTableName)
            WHERE sourceID = ?
            """,
            arguments: [sourceID]
        )
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
