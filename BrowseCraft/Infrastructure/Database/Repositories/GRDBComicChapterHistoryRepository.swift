import Foundation
import GRDB

// 中文注释：GRDBComicChapterHistoryRepository 通过 SQLite 保存漫画章节阅读历史。

/// 中文注释：保存时按 userID/sourceID/comicItemID/chapterKey upsert，避免同一章节重复插入。
final class GRDBComicChapterHistoryRepository: ComicChapterHistoryRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func save(_ history: ComicChapterHistory) throws {
        let record: ComicChapterHistoryRecord = ComicChapterHistoryRecord(history: history)

        try self.database.queue.write { database in
            try Self.upsert(record, in: database)
        }
    }

    func fetchHistory(userID: String) throws -> [ComicChapterHistory] {
        return try self.database.queue.read { database in
            let records: [ComicChapterHistoryRecord] = try ComicChapterHistoryRecord
                .filter(ComicChapterHistoryRecord.Columns.userID == userID)
                .order(ComicChapterHistoryRecord.Columns.visitedAt.desc)
                .fetchAll(database)

            return records.map { record in
                return record.domainModel()
            }
        }
    }

    /// 中文注释：当前来源读过的全部章节，最近的在前；走 `idx_comic_chapter_history_source`（库页瓷砖与进度角标一次读齐）。
    func fetchHistory(userID: String, sourceID: String) throws -> [ComicChapterHistory] {
        return try self.database.queue.read { database in
            let records: [ComicChapterHistoryRecord] = try ComicChapterHistoryRecord
                .filter(ComicChapterHistoryRecord.Columns.userID == userID)
                .filter(ComicChapterHistoryRecord.Columns.sourceID == sourceID)
                .order(ComicChapterHistoryRecord.Columns.visitedAt.desc)
                .fetchAll(database)

            return records.map { record in
                return record.domainModel()
            }
        }
    }

    /// 中文注释：每部作品最近读的那一章——子查询取每个 (userID, sourceID, comicItemID) 的最大 `visitedAt`，
    /// 只把这些行读进内存；历史页一部作品一行，不必先读全部章节再在内存里挑（2026-10-10 复审 B-2）。
    /// `visitedAt` 并列时会多出同作品的行，调用方按作品再去一次重。
    func fetchLatestPerWork(userID: String) throws -> [ComicChapterHistory] {
        return try self.database.queue.read { database in
            let records: [ComicChapterHistoryRecord] = try ComicChapterHistoryRecord.fetchAll(
                database,
                sql: """
                SELECT h.* FROM \(ComicChapterHistoryRecord.databaseTableName) h
                WHERE h.userID = ?
                  AND h.visitedAt = (
                    SELECT MAX(visitedAt) FROM \(ComicChapterHistoryRecord.databaseTableName)
                    WHERE userID = h.userID AND sourceID = h.sourceID AND comicItemID = h.comicItemID
                  )
                ORDER BY h.visitedAt DESC
                """,
                arguments: [userID]
            )

            return records.map { record in
                return record.domainModel()
            }
        }
    }

    func fetchLatest(
        userID: String,
        sourceID: String,
        comicItemID: String
    ) throws -> ComicChapterHistory? {
        return try self.database.queue.read { database in
            let record: ComicChapterHistoryRecord? = try ComicChapterHistoryRecord
                .filter(ComicChapterHistoryRecord.Columns.userID == userID)
                .filter(ComicChapterHistoryRecord.Columns.sourceID == sourceID)
                .filter(ComicChapterHistoryRecord.Columns.comicItemID == comicItemID)
                .order(ComicChapterHistoryRecord.Columns.visitedAt.desc)
                .fetchOne(database)

            return record?.domainModel()
        }
    }

    /// 中文注释：本作品读过的每一章，最近的在前；详情页据此标已读与「上次读到」（设计第六、七节）。走现有唯一键的前三列。
    func fetchHistory(
        userID: String,
        sourceID: String,
        comicItemID: String
    ) throws -> [ComicChapterHistory] {
        return try self.database.queue.read { database in
            let records: [ComicChapterHistoryRecord] = try ComicChapterHistoryRecord
                .filter(ComicChapterHistoryRecord.Columns.userID == userID)
                .filter(ComicChapterHistoryRecord.Columns.sourceID == sourceID)
                .filter(ComicChapterHistoryRecord.Columns.comicItemID == comicItemID)
                .order(ComicChapterHistoryRecord.Columns.visitedAt.desc)
                .fetchAll(database)

            return records.map { record in
                return record.domainModel()
            }
        }
    }

    func delete(_ history: ComicChapterHistory) throws {
        try self.delete([history])
    }

    /// 中文注释：批量删除在一个写事务里完成，不再每条一个事务。
    func delete(_ histories: [ComicChapterHistory]) throws {
        guard histories.isEmpty == false else {
            return
        }
        let records: [ComicChapterHistoryRecord] = histories.map(ComicChapterHistoryRecord.init(history:))

        try self.database.queue.write { database in
            for record: ComicChapterHistoryRecord in records {
                try database.execute(
                    sql: """
                    DELETE FROM \(ComicChapterHistoryRecord.databaseTableName)
                    WHERE userID = ? AND sourceID = ? AND comicItemID = ? AND chapterKey = ?
                    """,
                    arguments: [
                        record.userID,
                        record.sourceID,
                        record.comicItemID,
                        record.chapterKey
                    ]
                )
            }
        }
    }

    private static func upsert(_ record: ComicChapterHistoryRecord, in database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO \(ComicChapterHistoryRecord.databaseTableName)
                (userID, sourceID, comicItemID, comicTitle, chapterID, chapterKey, chapterURL, chapterTitle, visitedAt, coverURL, lastReaderPageURL, lastPageImageURL, lastPageImageCacheKey, lastPageIndex, pageCount, previousChapterURL, nextChapterURL, previousChapterTitle, nextChapterTitle, sourceSnapshotJSON)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(userID, sourceID, comicItemID, chapterKey) DO UPDATE SET
                comicTitle = excluded.comicTitle,
                chapterID = excluded.chapterID,
                chapterURL = excluded.chapterURL,
                chapterTitle = excluded.chapterTitle,
                visitedAt = excluded.visitedAt,
                coverURL = excluded.coverURL,
                lastReaderPageURL = excluded.lastReaderPageURL,
                lastPageImageURL = excluded.lastPageImageURL,
                lastPageImageCacheKey = excluded.lastPageImageCacheKey,
                lastPageIndex = excluded.lastPageIndex,
                pageCount = excluded.pageCount,
                previousChapterURL = excluded.previousChapterURL,
                nextChapterURL = excluded.nextChapterURL,
                previousChapterTitle = excluded.previousChapterTitle,
                nextChapterTitle = excluded.nextChapterTitle,
                sourceSnapshotJSON = excluded.sourceSnapshotJSON
            """,
            arguments: [
                record.userID,
                record.sourceID,
                record.comicItemID,
                record.comicTitle,
                record.chapterID,
                record.chapterKey,
                record.chapterURL,
                record.chapterTitle,
                record.visitedAt,
                record.coverURL,
                record.lastReaderPageURL,
                record.lastPageImageURL,
                record.lastPageImageCacheKey,
                record.lastPageIndex,
                record.pageCount,
                record.previousChapterURL,
                record.nextChapterURL,
                record.previousChapterTitle,
                record.nextChapterTitle,
                record.sourceSnapshotJSON
            ]
        )
    }
}
