import Foundation
import GRDB

// 中文注释：GRDBVideoWatchHistoryRepository 通过 SQLite 保存视频观看历史。

/// 中文注释：保存时按作品级 key 覆盖旧记录，避免 History 页同一视频按剧集重复显示。
final class GRDBVideoWatchHistoryRepository: VideoWatchHistoryRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func save(_ history: VideoWatchHistory) throws {
        var record: VideoWatchHistoryRecord = VideoWatchHistoryRecord(history: history)
        record.vodID = Self.storageVodID(for: history)

        try self.database.queue.write { database in
            try Self.deleteExistingWorkHistory(for: record, in: database)
            try record.insert(database)
        }
    }

    func fetchHistory(userID: String) throws -> [VideoWatchHistory] {
        return try self.database.queue.read { database in
            let records: [VideoWatchHistoryRecord] = try VideoWatchHistoryRecord
                .filter(Column("userID") == userID)
                .order(Column("updatedAt").desc, Column("visitedAt").desc)
                .fetchAll(database)

            return records.map { record in
                return record.domainModel()
            }
        }
    }

    func fetchHistory(
        userID: String,
        sourceID: String,
        vodID: String,
        sourceIndex: Int,
        episodeIndex: Int
    ) throws -> VideoWatchHistory? {
        return try self.database.queue.read { database in
            let record: VideoWatchHistoryRecord? = try VideoWatchHistoryRecord
                .filter(Column("userID") == userID)
                .filter(Column("sourceID") == sourceID)
                .filter(Column("vodID") == vodID)
                .filter(Column("sourceIndex") == sourceIndex)
                .filter(Column("episodeIndex") == episodeIndex)
                .fetchOne(database)

            return record?.domainModel()
        }
    }

    private static func deleteExistingWorkHistory(
        for record: VideoWatchHistoryRecord,
        in database: Database
    ) throws {
        try database.execute(
            sql: """
            DELETE FROM \(VideoWatchHistoryRecord.databaseTableName)
            WHERE userID = ? AND sourceID = ? AND vodID = ?
            """,
            arguments: [
                record.userID,
                record.sourceID,
                record.vodID
            ]
        )

        if let detailURL: String = record.detailURL,
           detailURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            try database.execute(
                sql: """
                DELETE FROM \(VideoWatchHistoryRecord.databaseTableName)
                WHERE userID = ? AND sourceID = ? AND detailURL = ?
                """,
                arguments: [
                    record.userID,
                    record.sourceID,
                    detailURL
                ]
            )
        }

        try database.execute(
            sql: """
            DELETE FROM \(VideoWatchHistoryRecord.databaseTableName)
            WHERE userID = ? AND sourceID = ? AND videoTitle = ?
            """,
            arguments: [
                record.userID,
                record.sourceID,
                record.videoTitle
            ]
        )
    }

    private static func storageVodID(for history: VideoWatchHistory) -> String {
        let trimmedVodID: String = history.vodID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedVodID.isEmpty == false {
            return trimmedVodID
        }

        if let detailURL: URL = history.detailURL {
            return "detail::\(detailURL.absoluteString)"
        }

        return "title::\(history.videoTitle)"
    }
}
