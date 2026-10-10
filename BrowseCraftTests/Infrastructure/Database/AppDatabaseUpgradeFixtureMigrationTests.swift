import BrowseCraftCore
import BrowseCraftDomain
import Foundation
import GRDB
import Testing
@testable import BrowseCraft

// 中文注释：v7 / v8 / v9 三步迁移在真实迁移链上的「上一正式版本升级」固定输入（`BCA-DB-003`，2026-10-10 复审合同 3 补齐）：
// 每条用例都先迁到上一版、按当时的列写入数据，再迁到最新——旧行原样、新列取缺省、外键检查干净。
// v6 的升级夹具在 `RemoveRSSMigrationTests`，v10 的在 `SourcesCatalogRuleFingerprintMigrationTests`；以后每加一步迁移照这里再加一条。
struct AppDatabaseUpgradeFixtureMigrationTests {
    private static let userID: String = "u1"
    private static let now: Date = Date(timeIntervalSince1970: 1_789_300_000)

    // MARK: - v7.users-add-coin

    @Test func upgradingFromV6AddsCoinColumnsWithZeroDefaultsAndKeepsUsers() throws {
        let queue: DatabaseQueue = try Self.makeQueue()
        let migrator: DatabaseMigrator = AppDatabaseMigrations.makeMigrator()
        try migrator.migrate(queue, upTo: AppDatabaseMigrations.removeRSSIdentifier)

        try queue.write { database in
            // 中文注释：`insertUser` 只写 v1 的列，在 v6 的 users 上也能插。
            try AppUserRecord.insertUser(id: Self.userID, displayName: "旧版用户", in: database)
        }
        let columnsBefore: [String] = try queue.read { database in
            try database.columns(in: "users").map(\.name)
        }
        #expect(columnsBefore.contains("coinBalance") == false)
        #expect(columnsBefore.contains("coinRevision") == false)

        try migrator.migrate(queue)

        try queue.read { database in
            let columns: [String] = try database.columns(in: "users").map(\.name)
            #expect(columns.contains("coinBalance"))
            #expect(columns.contains("coinRevision"))
            let record: AppUserRecord? = try AppUserRecord.fetchOne(database, key: Self.userID)
            #expect(record?.displayName == "旧版用户")
            #expect(record?.coinBalance == 0)
            #expect(record?.coinRevision == 0)
            #expect(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM users") == 1)
            let violations: [Row] = try Row.fetchAll(database, sql: "PRAGMA foreign_key_check")
            #expect(violations.isEmpty)
        }
    }

    // MARK: - v8.history-sync-ledger

    @Test func upgradingFromV7CreatesAnEmptyLedgerKeyedToUsersAndKeepsHistory() throws {
        let queue: DatabaseQueue = try Self.makeQueue()
        let migrator: DatabaseMigrator = AppDatabaseMigrations.makeMigrator()
        try migrator.migrate(queue, upTo: AppDatabaseMigrations.usersAddCoinIdentifier)

        let history: ComicChapterHistory = Self.makeComicHistory(chapter: 3)
        try queue.write { database in
            try AppUserRecord.insertUser(id: Self.userID, in: database)
            try insertComicChapterHistoryRowAsOfV8(history, in: database)
        }
        let ledgerExistedBefore: Bool = try queue.read { database in
            try database.tableExists("history_sync_ledger")
        }
        #expect(ledgerExistedBefore == false)

        try migrator.migrate(queue)

        try queue.read { database in
            #expect(try database.tableExists("history_sync_ledger"))
            // 中文注释：账本升级时为空——本机现有历史在下一轮同步按「账本里没有」当作新增登记，不在迁移里预填。
            #expect(try HistorySyncLedgerRecord.fetchCount(database) == 0)
            let primaryKey: [String] = try database.primaryKey("history_sync_ledger").columns
            #expect(primaryKey == ["userID", "kind", "sourceID", "workKey"])
            let foreignKeys: [ForeignKeyInfo] = try database.foreignKeys(on: "history_sync_ledger")
            #expect(foreignKeys.map(\.destinationTable) == ["users"])
            let kept: ComicChapterHistoryRecord? = try ComicChapterHistoryRecord
                .filter(ComicChapterHistoryRecord.Columns.userID == Self.userID)
                .fetchOne(database)
            #expect(kept?.chapterTitle == history.chapterTitle)
            let violations: [Row] = try Row.fetchAll(database, sql: "PRAGMA foreign_key_check")
            #expect(violations.isEmpty)
        }

        // 中文注释：外键真的接到 users 上——没有这个用户的账本行插不进去。
        #expect(throws: DatabaseError.self) {
            try queue.write { database in
                var orphan: HistorySyncLedgerRecord = HistorySyncLedgerRecord(
                    userID: "nobody",
                    kind: "comic",
                    sourceID: history.sourceID,
                    workKey: history.comicItemID,
                    changedAt: Self.now,
                    deletedAt: nil
                )
                try orphan.insert(database)
            }
        }
    }

    // MARK: - v9.comic-chapter-history-add-page-count

    @Test func upgradingFromV8AddsANullPageCountAndKeepsComicHistory() throws {
        let queue: DatabaseQueue = try Self.makeQueue()
        let migrator: DatabaseMigrator = AppDatabaseMigrations.makeMigrator()
        try migrator.migrate(queue, upTo: AppDatabaseMigrations.historySyncLedgerIdentifier)

        let history: ComicChapterHistory = Self.makeComicHistory(chapter: 5, pageIndex: 12)
        try queue.write { database in
            try AppUserRecord.insertUser(id: Self.userID, in: database)
            try insertComicChapterHistoryRowAsOfV8(history, in: database)
        }
        let columnsBefore: [String] = try queue.read { database in
            try database.columns(in: "comic_chapter_history").map(\.name)
        }
        #expect(columnsBefore.contains("pageCount") == false)

        try migrator.migrate(queue)

        try queue.read { database in
            let columns: [String] = try database.columns(in: "comic_chapter_history").map(\.name)
            #expect(columns.contains("pageCount"))
            let record: ComicChapterHistoryRecord? = try ComicChapterHistoryRecord
                .filter(ComicChapterHistoryRecord.Columns.userID == Self.userID)
                .fetchOne(database)
            #expect(record?.chapterTitle == history.chapterTitle)
            #expect(record?.lastPageIndex == 12)
            // 中文注释：旧记录没有总页数，页面只写「第 N 页」。
            #expect(record?.pageCount == nil)
            #expect(record?.domainModel().pageCount == nil)
            let violations: [Row] = try Row.fetchAll(database, sql: "PRAGMA foreign_key_check")
            #expect(violations.isEmpty)
        }
    }

    // MARK: - 夹具

    private static func makeQueue() throws -> DatabaseQueue {
        let path: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftUpgradeFixtureMigrationTests-\(UUID().uuidString).sqlite")
            .path
        return try DatabaseQueue(path: path)
    }

    private static func makeComicHistory(chapter: Int, pageIndex: Int? = nil) -> ComicChapterHistory {
        let detailURL: URL = URL(string: "https://comic.example.test/work-1")!
        return ComicChapterHistory(
            userID: Self.userID,
            sourceID: "comic.test",
            comicItemID: "work-1",
            comicTitle: "作品一",
            chapterID: "chapter-\(chapter)",
            chapterKey: "chapter-\(chapter)",
            chapterURL: detailURL.appendingPathComponent("chapter-\(chapter)"),
            chapterTitle: "第 \(chapter) 话",
            visitedAt: Self.now,
            coverURL: nil,
            lastPageIndex: pageIndex,
            sourceSnapshot: nil
        )
    }
}

// 中文注释：v8 及更早的 comic_chapter_history 还没有 v9 加的 `pageCount`，按当时的列写 SQL——
// `ComicChapterHistoryRecord` 带着后来的列，整条 insert 会撞上「no such column」（与 `insertSourceRowAsOfV9` 同一个原因）。
func insertComicChapterHistoryRowAsOfV8(_ history: ComicChapterHistory, in database: Database) throws {
    let record: ComicChapterHistoryRecord = ComicChapterHistoryRecord(history: history)
    try database.execute(
        sql: """
        INSERT INTO comic_chapter_history (
            userID, sourceID, comicItemID, comicTitle, chapterID, chapterKey, chapterURL, chapterTitle, visitedAt,
            coverURL, lastReaderPageURL, lastPageImageURL, lastPageImageCacheKey, lastPageIndex,
            previousChapterURL, nextChapterURL, previousChapterTitle, nextChapterTitle, sourceSnapshotJSON
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        arguments: [
            record.userID, record.sourceID, record.comicItemID, record.comicTitle, record.chapterID, record.chapterKey,
            record.chapterURL, record.chapterTitle, record.visitedAt,
            record.coverURL, record.lastReaderPageURL, record.lastPageImageURL, record.lastPageImageCacheKey, record.lastPageIndex,
            record.previousChapterURL, record.nextChapterURL, record.previousChapterTitle, record.nextChapterTitle, record.sourceSnapshotJSON
        ]
    )
}
