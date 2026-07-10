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

    func delete(_ history: ComicChapterHistory) throws {
        let record: ComicChapterHistoryRecord = ComicChapterHistoryRecord(history: history)

        try self.database.queue.write { database in
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

    private static func upsert(_ record: ComicChapterHistoryRecord, in database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO \(ComicChapterHistoryRecord.databaseTableName)
                (userID, sourceID, comicItemID, comicTitle, chapterID, chapterKey, chapterURL, chapterTitle, visitedAt, coverURL, lastReaderPageURL, lastPageImageURL, lastPageImageCacheKey, lastPageIndex, previousChapterURL, nextChapterURL, sourceSnapshotJSON)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                previousChapterURL = excluded.previousChapterURL,
                nextChapterURL = excluded.nextChapterURL,
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
                record.previousChapterURL,
                record.nextChapterURL,
                record.sourceSnapshotJSON
            ]
        )
    }
}
