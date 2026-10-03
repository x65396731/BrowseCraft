import CloudKit
import Foundation
import GRDB
import Testing
@testable import BrowseCraft

// 中文注释：续看位置同步（docs/design/History-Resume-Sync-Design.md）：本机改动靠对比账本登记，
// 合并按时间与删除标记，来源不在本机的记录不写入。
struct HistoryEntrySyncServiceTests {
    private static let userID: String = AppUser.localDefaultID
    private static let scope: CloudAccountScope = .localDefault

    @Test func registersLocalHistoryAndUploadsOneRecordPerWork() async throws {
        let database: AppDatabase = try Self.makeDatabase(sourceIDs: ["src"])
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        let service: HistoryEntrySyncService = Self.makeService(database: database, cloudStore: cloudStore)
        try Self.insertComic(database, comicItemID: "comic-1", chapterKey: "ch-1", visitedAt: 100, pageIndex: 3)
        try Self.insertComic(database, comicItemID: "comic-1", chapterKey: "ch-2", visitedAt: 200, pageIndex: 7)
        try Self.insertVideo(database, workKey: "vod::9", vodID: "9", updatedAt: 300, playbackTime: 42)
        try Self.insertBook(database, detailURL: "https://b.example/book/1", visitedAt: 400, locatorJSON: "{\"href\":\"c1\"}")

        _ = try await service.downloadHistoryEntries(accountScope: Self.scope)
        let result: HistoryEntrySyncResult = try await service.uploadHistoryEntries(accountScope: Self.scope)

        #expect(result.uploadedCount == 3)
        let comic: HistoryEntryCloudPayload? = cloudStore.savedHistoryEntriesByID[
            HistoryEntryIdentity(kind: "comic", sourceID: "src", workKey: "comic-1")
        ]
        #expect(comic?.unitKey == "ch-2")
        #expect(comic?.pageIndex == 7)
        #expect(comic?.updatedAt == Date(timeIntervalSince1970: 200))
        let video: HistoryEntryCloudPayload? = cloudStore.savedHistoryEntriesByID[
            HistoryEntryIdentity(kind: "video", sourceID: "src", workKey: "vod::9")
        ]
        #expect(video?.itemID == "9")
        #expect(video?.playbackTime == 42)
        #expect(video?.unitURL == "https://v.example/play/9")
        let book: HistoryEntryCloudPayload? = cloudStore.savedHistoryEntriesByID[
            HistoryEntryIdentity(kind: "book", sourceID: "src", workKey: "https://b.example/book/1")
        ]
        #expect(book?.itemID == "book-item")
        #expect(book?.locatorJSON == "{\"href\":\"c1\"}")

        // 没有新改动时第二轮什么都不传。
        _ = try await service.downloadHistoryEntries(accountScope: Self.scope)
        let second: HistoryEntrySyncResult = try await service.uploadHistoryEntries(accountScope: Self.scope)
        #expect(second.uploadedCount == 0)
        #expect(try Self.queueCount(database) == 0)
    }

    @Test func historyOfMissingSourceIsNotUploaded() async throws {
        let database: AppDatabase = try Self.makeDatabase(sourceIDs: [])
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        let service: HistoryEntrySyncService = Self.makeService(database: database, cloudStore: cloudStore)
        try Self.insertComic(database, comicItemID: "comic-1", chapterKey: "ch-1", visitedAt: 100, pageIndex: 1)

        _ = try await service.downloadHistoryEntries(accountScope: Self.scope)
        let result: HistoryEntrySyncResult = try await service.uploadHistoryEntries(accountScope: Self.scope)

        #expect(result.uploadedCount == 0)
        #expect(cloudStore.savedHistoryEntriesByID.isEmpty)
    }

    @Test func appliesRemoteEntriesWithoutEchoingThemBack() async throws {
        let database: AppDatabase = try Self.makeDatabase(sourceIDs: ["src"])
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        let service: HistoryEntrySyncService = Self.makeService(database: database, cloudStore: cloudStore)
        cloudStore.pendingHistoryEntries = [
            Self.payload(kind: "comic", workKey: "comic-1", updatedAt: 500, unitKey: "ch-5", pageIndex: 12),
            Self.payload(kind: "video", workKey: "vod::9", updatedAt: 510, unitKey: "ep-2", unitURL: "https://v.example/play/9-2", playbackTime: 77),
            Self.payload(kind: "book", workKey: "https://b.example/book/1", updatedAt: 520, itemID: "book-item", unitURL: "https://b.example/c/3", locatorJSON: "{\"href\":\"c3\"}")
        ]

        let result: HistoryEntrySyncResult = try await service.downloadHistoryEntries(accountScope: Self.scope)

        #expect(result.downloadedCount == 3)
        let comicPage: Int? = try await database.queue.read { database in
            try Int.fetchOne(database, sql: "SELECT lastPageIndex FROM comic_chapter_history WHERE comicItemID = 'comic-1' AND chapterKey = 'ch-5'")
        }
        #expect(comicPage == 12)
        let videoRow: Row? = try await database.queue.read { database in
            try Row.fetchOne(database, sql: "SELECT vodID, lastPlaybackTime, playPageURL, candidateMediaKind FROM video_watch_history WHERE workKey = 'vod::9'")
        }
        #expect(videoRow?["vodID"] == "9")
        #expect(videoRow?["lastPlaybackTime"] == 77.0)
        #expect(videoRow?["candidateMediaKind"] == "unknown")
        let bookItemID: String? = try await database.queue.read { database in
            try String.fetchOne(database, sql: "SELECT bookItemID FROM book_reading_history WHERE detailURL = 'https://b.example/book/1'")
        }
        #expect(bookItemID == "book-item")
        let locator: String? = try await database.queue.read { database in
            try String.fetchOne(database, sql: "SELECT locatorJSON FROM book_reading_progress")
        }
        #expect(locator == "{\"href\":\"c3\"}")

        let upload: HistoryEntrySyncResult = try await service.uploadHistoryEntries(accountScope: Self.scope)
        #expect(upload.uploadedCount == 0)
        _ = try await service.downloadHistoryEntries(accountScope: Self.scope)
        let secondUpload: HistoryEntrySyncResult = try await service.uploadHistoryEntries(accountScope: Self.scope)
        #expect(secondUpload.uploadedCount == 0)
    }

    @Test func remoteEntryForMissingSourceIsSkipped() async throws {
        let database: AppDatabase = try Self.makeDatabase(sourceIDs: [])
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        let service: HistoryEntrySyncService = Self.makeService(database: database, cloudStore: cloudStore)
        cloudStore.pendingHistoryEntries = [
            Self.payload(kind: "comic", workKey: "comic-1", updatedAt: 500, unitKey: "ch-5", pageIndex: 12),
            Self.payload(kind: "podcast", workKey: "x", updatedAt: 500)
        ]

        let result: HistoryEntrySyncResult = try await service.downloadHistoryEntries(accountScope: Self.scope)

        #expect(result.downloadedCount == 0)
        #expect(result.skippedCount == 2)
        #expect(try Self.comicCount(database) == 0)
    }

    @Test func newerLocalHistoryWinsOverOlderRemote() async throws {
        let database: AppDatabase = try Self.makeDatabase(sourceIDs: ["src"])
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        let service: HistoryEntrySyncService = Self.makeService(database: database, cloudStore: cloudStore)
        try Self.insertComic(database, comicItemID: "comic-1", chapterKey: "ch-9", visitedAt: 900, pageIndex: 2)
        cloudStore.pendingHistoryEntries = [
            Self.payload(kind: "comic", workKey: "comic-1", updatedAt: 500, unitKey: "ch-5", pageIndex: 12)
        ]

        let download: HistoryEntrySyncResult = try await service.downloadHistoryEntries(accountScope: Self.scope)
        let upload: HistoryEntrySyncResult = try await service.uploadHistoryEntries(accountScope: Self.scope)

        #expect(download.downloadedCount == 0)
        #expect(upload.uploadedCount == 1)
        #expect(cloudStore.savedHistoryEntriesByID.values.first?.unitKey == "ch-9")
        #expect(try Self.comicCount(database) == 1)
    }

    @Test func localDeletionUploadsTombstoneAndRestoreUploadsLiveAgain() async throws {
        let database: AppDatabase = try Self.makeDatabase(sourceIDs: ["src"])
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        let clock: TestClock = TestClock(1_000)
        let service: HistoryEntrySyncService = Self.makeService(database: database, cloudStore: cloudStore, clock: clock)
        let identity: HistoryEntryIdentity = HistoryEntryIdentity(kind: "comic", sourceID: "src", workKey: "comic-1")
        try Self.insertComic(database, comicItemID: "comic-1", chapterKey: "ch-1", visitedAt: 100, pageIndex: 1)
        _ = try await service.downloadHistoryEntries(accountScope: Self.scope)
        _ = try await service.uploadHistoryEntries(accountScope: Self.scope)

        try await database.queue.write { database in
            try database.execute(sql: "DELETE FROM comic_chapter_history")
        }
        clock.set(2_000)
        _ = try await service.downloadHistoryEntries(accountScope: Self.scope)
        _ = try await service.uploadHistoryEntries(accountScope: Self.scope)
        #expect(cloudStore.savedHistoryEntriesByID[identity]?.deletedAt == Date(timeIntervalSince1970: 2_000))

        // 撤销删除：行按原来的时间写回，上传的更新时间必须盖过删除标记。
        try Self.insertComic(database, comicItemID: "comic-1", chapterKey: "ch-1", visitedAt: 100, pageIndex: 1)
        clock.set(3_000)
        _ = try await service.downloadHistoryEntries(accountScope: Self.scope)
        _ = try await service.uploadHistoryEntries(accountScope: Self.scope)
        let restored: HistoryEntryCloudPayload? = cloudStore.savedHistoryEntriesByID[identity]
        #expect(restored?.deletedAt == nil)
        #expect(restored?.updatedAt == Date(timeIntervalSince1970: 3_000))
    }

    @Test func remoteTombstoneDeletesLocalHistoryOfThatWork() async throws {
        let database: AppDatabase = try Self.makeDatabase(sourceIDs: ["src"])
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        let service: HistoryEntrySyncService = Self.makeService(database: database, cloudStore: cloudStore)
        try Self.insertComic(database, comicItemID: "comic-1", chapterKey: "ch-1", visitedAt: 100, pageIndex: 1)
        try Self.insertComic(database, comicItemID: "comic-2", chapterKey: "ch-1", visitedAt: 100, pageIndex: 1)
        _ = try await service.downloadHistoryEntries(accountScope: Self.scope)
        _ = try await service.uploadHistoryEntries(accountScope: Self.scope)
        cloudStore.pendingHistoryEntries = [
            HistoryEntryCloudPayload.tombstone(
                identity: HistoryEntryIdentity(kind: "comic", sourceID: "src", workKey: "comic-1"),
                deletedAt: Date(timeIntervalSince1970: 700)
            )
        ]

        let result: HistoryEntrySyncResult = try await service.downloadHistoryEntries(accountScope: Self.scope)
        let upload: HistoryEntrySyncResult = try await service.uploadHistoryEntries(accountScope: Self.scope)

        #expect(result.deletedCount == 1)
        #expect(try Self.comicCount(database) == 1)
        // 云端来的删除不应再被当成本机删除传回去。
        #expect(upload.uploadedCount == 0)
    }

    @Test func identityRoundTripsThroughSyncEntityID() {
        let identity: HistoryEntryIdentity = HistoryEntryIdentity(
            kind: "book",
            sourceID: "src:with\"quotes",
            workKey: "https://b.example/book/1?a=[1,2]"
        )
        #expect(HistoryEntryIdentity(syncEntityID: identity.syncEntityID) == identity)
        #expect(HistoryEntryIdentity(syncEntityID: "not json") == nil)
    }

    @Test func recordMapperRoundTripsEveryField() throws {
        let mapper: CloudKitRecordMapper = CloudKitRecordMapper()
        var payload: HistoryEntryCloudPayload = Self.payload(
            kind: "video",
            workKey: "vod::9",
            updatedAt: 510,
            itemID: "9",
            unitKey: "ep-2",
            unitURL: "https://v.example/play/9-2",
            playbackTime: 77
        )
        payload.sourceIndex = 1
        payload.episodeIndex = 4
        payload.duration = 1_200
        payload.detailURL = "https://v.example/detail/9"
        payload.visitedAt = Date(timeIntervalSince1970: 505)
        let record: CKRecord = CKRecord(
            recordType: CloudKitRecordMapper.historyEntryRecordType,
            recordID: mapper.recordID(forHistoryEntry: payload.identity)
        )

        try mapper.apply(payload, to: record)

        #expect(try mapper.historyEntryPayload(from: record) == payload)
    }

    @Test func validatorRejectsURLWithCredentials() {
        let validator: CloudSyncPayloadSecurityValidator = CloudSyncPayloadSecurityValidator()
        let clean: HistoryEntryCloudPayload = Self.payload(kind: "video", workKey: "vod::9", updatedAt: 1, unitURL: "https://v.example/play/9")
        let leaking: HistoryEntryCloudPayload = Self.payload(kind: "video", workKey: "vod::9", updatedAt: 1, unitURL: "https://user:secret@v.example/play/9")

        #expect(throws: Never.self) {
            try validator.validate(clean)
        }
        #expect(throws: CloudSyncPayloadSecurityError.self) {
            try validator.validate(leaking)
        }
    }

    // MARK: - 准备数据

    private static func makeDatabase(sourceIDs: [String]) throws -> AppDatabase {
        let path: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftHistorySyncTests-\(UUID().uuidString).sqlite")
            .path
        let database: AppDatabase = try AppDatabase(path: path)
        try database.queue.write { database in
            try AppUserRecord.insertLocalDefaultUser(in: database)
            for sourceID: String in sourceIDs {
                var record: SourceRecord = SourceRecord(
                    userID: Self.userID,
                    id: sourceID,
                    name: sourceID,
                    baseURL: "https://example.com",
                    type: "html",
                    kind: "comic",
                    configJSON: "{}",
                    enabled: true,
                    createdAt: Date(timeIntervalSince1970: 1),
                    updatedAt: Date(timeIntervalSince1970: 1),
                    deletedAt: nil
                )
                try record.insert(database)
            }
        }
        return database
    }

    private static func makeService(
        database: AppDatabase,
        cloudStore: MockCloudRecordStore,
        clock: TestClock = TestClock(10_000)
    ) -> HistoryEntrySyncService {
        return HistoryEntrySyncService(
            localStore: GRDBHistoryEntrySyncLocalStore(database: database, now: { clock.now }),
            cloudStore: cloudStore
        )
    }

    private static func insertComic(
        _ database: AppDatabase,
        comicItemID: String,
        chapterKey: String,
        visitedAt: TimeInterval,
        pageIndex: Int
    ) throws {
        try database.queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO comic_chapter_history
                    (userID, sourceID, comicItemID, comicTitle, chapterKey, chapterURL, chapterTitle, visitedAt, lastPageIndex)
                VALUES (?, 'src', ?, 'Comic', ?, 'https://c.example/ch', 'Chapter', ?, ?)
                """,
                arguments: [Self.userID, comicItemID, chapterKey, Date(timeIntervalSince1970: visitedAt), pageIndex]
            )
        }
    }

    private static func insertVideo(
        _ database: AppDatabase,
        workKey: String,
        vodID: String,
        updatedAt: TimeInterval,
        playbackTime: Double
    ) throws {
        try database.queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO video_watch_history
                    (userID, sourceID, vodID, workKey, videoTitle, episodeKey, sourceIndex, episodeIndex,
                     playPageURL, candidateMediaURL, candidateMediaKind, lastPlaybackTime, visitedAt, updatedAt)
                VALUES (?, 'src', ?, ?, 'Video', 'ep-1', 0, 0, ?, 'https://cdn.example/expiring.m3u8', 'm3u8', ?, ?, ?)
                """,
                arguments: [
                    Self.userID, vodID, workKey, "https://v.example/play/\(vodID)", playbackTime,
                    Date(timeIntervalSince1970: updatedAt), Date(timeIntervalSince1970: updatedAt)
                ]
            )
        }
    }

    private static func insertBook(
        _ database: AppDatabase,
        detailURL: String,
        visitedAt: TimeInterval,
        locatorJSON: String
    ) throws {
        try database.queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO book_reading_history (userID, sourceID, detailURL, bookItemID, bookTitle, visitedAt)
                VALUES (?, 'src', ?, 'book-item', 'Book', ?)
                """,
                arguments: [Self.userID, detailURL, Date(timeIntervalSince1970: visitedAt)]
            )
            try database.execute(
                sql: """
                INSERT INTO book_reading_progress (bookID, userID, locatorJSON, totalProgression, updatedAt)
                VALUES (?, ?, ?, 0.5, ?)
                """,
                arguments: [
                    SiteBookIdentity.bookID(sourceID: "src", detailURL: detailURL).uuidString,
                    Self.userID, locatorJSON, Date(timeIntervalSince1970: visitedAt)
                ]
            )
        }
    }

    private static func payload(
        kind: String,
        workKey: String,
        updatedAt: TimeInterval,
        itemID: String? = nil,
        unitKey: String? = nil,
        unitURL: String? = nil,
        pageIndex: Int? = nil,
        playbackTime: Double? = nil,
        locatorJSON: String? = nil
    ) -> HistoryEntryCloudPayload {
        return HistoryEntryCloudPayload(
            schemaVersion: HistoryEntryCloudPayload.currentSchemaVersion,
            kind: kind,
            sourceID: "src",
            workKey: workKey,
            itemID: itemID,
            title: "Title",
            unitKey: unitKey,
            unitTitle: "Unit",
            unitURL: unitURL,
            pageIndex: pageIndex,
            playbackTime: playbackTime,
            locatorJSON: locatorJSON,
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }

    private static func queueCount(_ database: AppDatabase) throws -> Int {
        return try database.queue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sync_queue") ?? 0
        }
    }

    private static func comicCount(_ database: AppDatabase) throws -> Int {
        return try database.queue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(DISTINCT comicItemID) FROM comic_chapter_history") ?? 0
        }
    }
}

/// 中文注释：测试里手动拨的时钟。
private final class TestClock: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var value: TimeInterval

    init(_ value: TimeInterval) {
        self.value = value
    }

    var now: Date {
        self.lock.lock()
        defer { self.lock.unlock() }
        return Date(timeIntervalSince1970: self.value)
    }

    func set(_ value: TimeInterval) {
        self.lock.lock()
        self.value = value
        self.lock.unlock()
    }
}
