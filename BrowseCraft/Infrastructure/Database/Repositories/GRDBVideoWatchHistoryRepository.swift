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
        let record: VideoWatchHistoryRecord = VideoWatchHistoryRecord(history: history)

        try self.database.queue.write { database in
            try Self.deleteExistingWorkHistory(for: record, in: database)
            try Self.upsert(record, in: database)
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

    func delete(_ history: VideoWatchHistory) throws {
        let record: VideoWatchHistoryRecord = VideoWatchHistoryRecord(history: history)

        try self.database.queue.write { database in
            try database.execute(
                sql: """
                DELETE FROM \(VideoWatchHistoryRecord.databaseTableName)
                WHERE userID = ? AND sourceID = ? AND workKey = ?
                """,
                arguments: [
                    record.userID,
                    record.sourceID,
                    record.workKey
                ]
            )
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
            WHERE userID = ? AND sourceID = ? AND workKey = ?
            """,
            arguments: [
                record.userID,
                record.sourceID,
                record.workKey
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

    private static func upsert(_ record: VideoWatchHistoryRecord, in database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO \(VideoWatchHistoryRecord.databaseTableName)
                (userID, sourceID, vodID, workKey, videoTitle, episodeTitle, episodeKey, sourceIndex, episodeIndex, detailURL, playPageURL, candidateMediaURL, candidateMediaKind, playbackStatusJSON, playbackRequestConfigJSON, coverURL, sourceName, lastPlaybackTime, duration, visitedAt, updatedAt, previousEpisodeURL, nextEpisodeURL)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(userID, sourceID, workKey) DO UPDATE SET
                vodID = excluded.vodID,
                videoTitle = excluded.videoTitle,
                episodeTitle = excluded.episodeTitle,
                episodeKey = excluded.episodeKey,
                sourceIndex = excluded.sourceIndex,
                episodeIndex = excluded.episodeIndex,
                detailURL = excluded.detailURL,
                playPageURL = excluded.playPageURL,
                candidateMediaURL = excluded.candidateMediaURL,
                candidateMediaKind = excluded.candidateMediaKind,
                playbackStatusJSON = excluded.playbackStatusJSON,
                playbackRequestConfigJSON = excluded.playbackRequestConfigJSON,
                coverURL = excluded.coverURL,
                sourceName = excluded.sourceName,
                lastPlaybackTime = excluded.lastPlaybackTime,
                duration = excluded.duration,
                visitedAt = excluded.visitedAt,
                updatedAt = excluded.updatedAt,
                previousEpisodeURL = excluded.previousEpisodeURL,
                nextEpisodeURL = excluded.nextEpisodeURL
            """,
            arguments: [
                record.userID,
                record.sourceID,
                record.vodID,
                record.workKey,
                record.videoTitle,
                record.episodeTitle,
                record.episodeKey,
                record.sourceIndex,
                record.episodeIndex,
                record.detailURL,
                record.playPageURL,
                record.candidateMediaURL,
                record.candidateMediaKind,
                record.playbackStatusJSON,
                record.playbackRequestConfigJSON,
                record.coverURL,
                record.sourceName,
                record.lastPlaybackTime,
                record.duration,
                record.visitedAt,
                record.updatedAt,
                record.previousEpisodeURL,
                record.nextEpisodeURL
            ]
        )
    }
}
