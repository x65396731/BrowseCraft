import Foundation
import Testing
import GRDB
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftDomain

struct SyncRepositoryTests {
    @Test func syncQueueMergesChangesAndClearsFailureState() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let repository: GRDBSyncQueueRepository = GRDBSyncQueueRepository(database: database)

        try repository.enqueue(entityType: .source, entityID: "source-1", operation: .upsert)
        try repository.markFailed(
            id: "local.default|source:source-1",
            errorMessage: "Network unavailable"
        )

        var pending: [SyncQueueItem] = try repository.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].retryCount == 1)
        #expect(pending[0].lastError == "Network unavailable")

        try repository.enqueue(entityType: .source, entityID: "source-1", operation: .delete)

        pending = try repository.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].entityType == .source)
        #expect(pending[0].entityID == "source-1")
        #expect(pending[0].operation == .delete)
        #expect(pending[0].retryCount == 0)
        #expect(pending[0].lastError == nil)

        try repository.markSynced(id: "local.default|source:source-1")
        #expect(try repository.fetchPending(limit: 10).isEmpty)
    }

    @Test func syncStateSavesAndUpdatesCloudCursor() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let repository: GRDBSyncStateRepository = GRDBSyncStateRepository(database: database)
        let initialDate: Date = Date(timeIntervalSince1970: 100)
        let updatedDate: Date = Date(timeIntervalSince1970: 200)

        try repository.saveState(
            SyncState(
                scope: "private",
                zoneName: "BrowseCraft",
                serverChangeTokenData: Data([1, 2, 3]),
                lastSyncedAt: initialDate,
                updatedAt: initialDate
            )
        )

        var state: SyncState? = try repository.fetchState(scope: "private", zoneName: "BrowseCraft")
        #expect(state?.serverChangeTokenData == Data([1, 2, 3]))
        #expect(state?.lastSyncedAt == initialDate)

        try repository.saveState(
            SyncState(
                scope: "private",
                zoneName: "BrowseCraft",
                serverChangeTokenData: Data([4, 5, 6]),
                lastSyncedAt: updatedDate,
                updatedAt: updatedDate
            )
        )

        state = try repository.fetchState(scope: "private", zoneName: "BrowseCraft")
        #expect(state?.serverChangeTokenData == Data([4, 5, 6]))
        #expect(state?.lastSyncedAt == updatedDate)
        #expect(state?.updatedAt == updatedDate)
    }

    @Test func staleUploadAcknowledgementDoesNotRemoveNewerQueueChange() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let localStore: GRDBSourceSyncLocalStore = GRDBSourceSyncLocalStore(database: database)
        let firstDate: Date = Date(timeIntervalSince1970: 100)
        let newerDate: Date = Date(timeIntervalSince1970: 200)

        try database.queue.write { database in
            try SyncQueueRecord.enqueue(
                accountScope: .localDefault,
                entityType: .source,
                entityID: "source-1",
                operation: .upsert,
                updatedAt: firstDate,
                in: database
            )
        }
        let original: SyncQueueItem = try #require(
            localStore.pendingUploads(accountScope: .localDefault).first?.queueItem
        )

        try database.queue.write { database in
            try SyncQueueRecord.enqueue(
                accountScope: .localDefault,
                entityType: .source,
                entityID: "source-1",
                operation: .delete,
                updatedAt: newerDate,
                in: database
            )
        }
        try localStore.removePendingUploads(
            acknowledgements: [SyncQueueAcknowledgement(item: original)]
        )

        let remaining: SyncQueueItem = try #require(
            localStore.pendingUploads(accountScope: .localDefault).first?.queueItem
        )
        #expect(remaining.operation == .delete)
        #expect(remaining.updatedAt == newerDate)
    }

    @Test func failedUploadWaitsUntilPersistedRetryDateAndNewChangeClearsDelay() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let failedAt: Date = Date(timeIntervalSince1970: 1_000)
        let accountScope: CloudAccountScope = .localDefault
        let localStore: GRDBSourceSyncLocalStore = GRDBSourceSyncLocalStore(
            database: database,
            now: { failedAt }
        )

        try database.queue.write { database in
            try SyncQueueRecord.enqueue(
                accountScope: accountScope,
                entityType: .source,
                entityID: "source-1",
                operation: .upsert,
                updatedAt: failedAt,
                in: database
            )
        }
        let queuedItem: SyncQueueItem = try #require(
            localStore.pendingUploads(accountScope: accountScope).first?.queueItem
        )
        try localStore.markPendingUploadsFailed([
            SyncQueueFailureUpdate(
                acknowledgement: SyncQueueAcknowledgement(item: queuedItem),
                errorMessage: "serverBusy",
                retryAfter: 60
            )
        ])

        #expect(try localStore.pendingUploads(accountScope: accountScope).isEmpty)
        let retryDate: Date = try #require(
            try GRDBCloudSyncEngineStore(database: database).earliestRetryDate(for: accountScope)
        )
        #expect(retryDate == failedAt.addingTimeInterval(60))

        let eligibleStore: GRDBSourceSyncLocalStore = GRDBSourceSyncLocalStore(
            database: database,
            now: { failedAt.addingTimeInterval(61) }
        )
        #expect(try eligibleStore.pendingUploads(accountScope: accountScope).count == 1)

        let changedAt: Date = failedAt.addingTimeInterval(30)
        try database.queue.write { database in
            try SyncQueueRecord.enqueue(
                accountScope: accountScope,
                entityType: .source,
                entityID: "source-1",
                operation: .delete,
                updatedAt: changedAt,
                in: database
            )
        }
        let changedItem: SyncQueueItem = try #require(
            localStore.pendingUploads(accountScope: accountScope).first?.queueItem
        )
        #expect(changedItem.operation == .delete)
        #expect(changedItem.nextRetryAt == nil)
    }

    @Test func deletedZoneRecoveryRequeuesOnlyActiveCloudData() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let accountScope: CloudAccountScope = .cloud(hash: "account-a")
        let engineStore: GRDBCloudSyncEngineStore = GRDBCloudSyncEngineStore(database: database)
        let changedAt: Date = Date(timeIntervalSince1970: 1_000)

        try database.queue.write { database in
            try AppUserRecord.insertLocalDefaultUser(in: database)
            var activeSource: SourceRecord = Self.sourceRecord(
                userID: AppUser.localDefaultID,
                id: "source-active",
                updatedAt: changedAt,
                deletedAt: nil
            )
            try activeSource.insert(database)
            var deletedSource: SourceRecord = Self.sourceRecord(
                userID: AppUser.localDefaultID,
                id: "source-deleted",
                updatedAt: changedAt,
                deletedAt: changedAt
            )
            try deletedSource.insert(database)
            var builtInSource: SourceRecord = Self.sourceRecord(
                userID: AppUser.localDefaultID,
                id: "built-in.plugin.example",
                updatedAt: changedAt,
                deletedAt: nil
            )
            try builtInSource.insert(database)

            var activeFavorite: FavoriteItemRecord = try FavoriteItemRecord(
                userID: AppUser.localDefaultID,
                item: Self.favoriteItem(),
                updatedAt: changedAt,
                deletedAt: nil
            )
            try activeFavorite.insert(database)
            var deletedFavorite: FavoriteItemRecord = try FavoriteItemRecord(
                userID: AppUser.localDefaultID,
                item: FavoriteContentItem(
                    id: "favorite-deleted",
                    sourceID: "source-active",
                    title: "Deleted",
                    detailURL: "https://example.test/deleted",
                    coverURL: nil,
                    kind: .comic,
                    latestText: nil,
                    updatedAt: changedAt,
                    favoritedAt: changedAt,
                    listOrder: nil,
                    listContext: nil,
                    sourceSnapshot: nil
                ),
                updatedAt: changedAt,
                deletedAt: changedAt
            )
            try deletedFavorite.insert(database)
        }
        try engineStore.saveState(Data([1, 2, 3]), for: accountScope)
        try engineStore.saveSystemFields(
            Data([4, 5, 6]),
            accountScope: accountScope,
            recordName: "old-record"
        )

        try engineStore.recoverDeletedZone(
            for: accountScope,
            strategy: .rebuildFromLocalData
        )

        let queueRecords: [SyncQueueRecord] = try database.queue.read { database in
            try SyncQueueRecord
                .filter(SyncQueueRecord.Columns.accountScope == accountScope.rawValue)
                .fetchAll(database)
        }
        #expect(queueRecords.count == 2)
        #expect(queueRecords.contains { $0.entityID == "source-active" })
        #expect(
            queueRecords.contains {
                $0.entityID == FavoriteItemIdentity(
                    sourceID: "source-1",
                    itemID: "favorite-1"
                ).syncEntityID
            }
        )
        #expect(try engineStore.loadState(for: accountScope) == nil)
        #expect(
            try engineStore.systemFields(
                accountScope: accountScope,
                recordName: "old-record"
            ) == nil
        )
    }

    @Test func purgedZoneRecoveryDeletesLocalCloudCacheWithoutRequeueing() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let accountScope: CloudAccountScope = .cloud(hash: "account-a")
        let engineStore: GRDBCloudSyncEngineStore = GRDBCloudSyncEngineStore(database: database)
        let changedAt: Date = Date(timeIntervalSince1970: 1_000)

        try database.queue.write { database in
            try AppUserRecord.insertLocalDefaultUser(in: database)
            var source: SourceRecord = Self.sourceRecord(
                userID: AppUser.localDefaultID,
                id: "source-active",
                updatedAt: changedAt,
                deletedAt: nil
            )
            try source.insert(database)
            var favorite: FavoriteItemRecord = try FavoriteItemRecord(
                userID: AppUser.localDefaultID,
                item: Self.favoriteItem(),
                updatedAt: changedAt,
                deletedAt: nil
            )
            try favorite.insert(database)
            try SyncQueueRecord.enqueue(
                accountScope: accountScope,
                entityType: .source,
                entityID: source.id,
                operation: .upsert,
                updatedAt: changedAt,
                in: database
            )
        }

        try engineStore.recoverDeletedZone(
            for: accountScope,
            strategy: .purgeLocalCloudData
        )

        let remainingCounts: (sources: Int, favorites: Int, queue: Int) = try database.queue.read {
            database in
            return (
                sources: try SourceRecord
                    .filter(SourceRecord.Columns.userID == AppUser.localDefaultID)
                    .fetchCount(database),
                favorites: try FavoriteItemRecord
                    .filter(FavoriteItemRecord.Columns.userID == AppUser.localDefaultID)
                    .fetchCount(database),
                queue: try SyncQueueRecord
                    .filter(SyncQueueRecord.Columns.accountScope == accountScope.rawValue)
                    .fetchCount(database)
            )
        }
        #expect(remainingCounts.sources == 0)
        #expect(remainingCounts.favorites == 0)
        #expect(remainingCounts.queue == 0)
    }

    @Test func sourceRepositorySoftDeletesAndEnqueuesUserSourceChanges() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        let queueRepository: GRDBSyncQueueRepository = GRDBSyncQueueRepository(database: database)
        let source: Source = Self.makePluginSource(id: "user-source-1")

        try sourceRepository.saveSource(source)

        var pending: [SyncQueueItem] = try queueRepository.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].entityType == .source)
        #expect(pending[0].entityID == "user-source-1")
        #expect(pending[0].operation == .upsert)

        try sourceRepository.deleteSource(id: "user-source-1")

        #expect(try sourceRepository.fetchSources().isEmpty)
        pending = try queueRepository.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].operation == .delete)

        let deletedAt: Date? = try database.queue.read { database in
            let record: SourceRecord? = try SourceRecord.fetchOne(
                database,
                key: ["userID": AppUser.localDefaultID, "id": "user-source-1"]
            )
            return record?.deletedAt
        }
        #expect(deletedAt != nil)
    }

    @Test func favoriteRepositoryEnqueuesFavoriteChanges() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        let queueRepository: GRDBSyncQueueRepository = GRDBSyncQueueRepository(database: database)

        try favoriteRepository.setFavorite(item: Self.favoriteItem(), isFavorite: true)

        let pending: [SyncQueueItem] = try queueRepository.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].entityType == .favoriteItem)
        #expect(
            pending[0].entityID == FavoriteItemIdentity(
                sourceID: "source-1",
                itemID: "favorite-1"
            ).syncEntityID
        )
        #expect(pending[0].operation == .upsert)
    }

    // 中文注释：`BCA-DB-004` / `BCA-DB-005`——删除来源在同一事务里删掉该用户该来源的三张历史表记录、给收藏写删除标记并入队、
    // 清空指向它的库当前选择；其他来源的记录不动。撤销把这些原样写回（含原访问时间、原收藏时间），队列里留下的是更新。
    @Test func sourceRepositoryCascadesHistoryAndFavoritesAndUndoRestoresThem() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        let queueRepository: GRDBSyncQueueRepository = GRDBSyncQueueRepository(database: database)
        let comics: GRDBComicChapterHistoryRepository = GRDBComicChapterHistoryRepository(database: database)
        let videos: GRDBVideoWatchHistoryRepository = GRDBVideoWatchHistoryRepository(database: database)
        let books: GRDBBookReadingHistoryRepository = GRDBBookReadingHistoryRepository(database: database)
        let libraryStates: GRDBUserLibraryStateRepository = GRDBUserLibraryStateRepository(database: database)
        let userID: String = AppUser.localDefaultID

        try sourceRepository.saveSource(Self.makePluginSource(id: "source-1"))
        try sourceRepository.saveSource(Self.makePluginSource(id: "built-in.keep"))
        let chapter1: ComicChapterHistory = Self.comicHistory(sourceID: "source-1", chapter: 1, pageIndex: 4)
        let chapter2: ComicChapterHistory = Self.comicHistory(sourceID: "source-1", chapter: 2, pageIndex: 17)
        try comics.save(chapter1)
        try comics.save(chapter2)
        try comics.save(Self.comicHistory(sourceID: "built-in.keep", chapter: 9))
        try videos.save(Self.videoHistory(sourceID: "source-1"))
        try books.save(Self.bookHistory(sourceID: "source-1"))
        let favoritedAt: Date = Date(timeIntervalSince1970: 60)
        try favoriteRepository.restoreFavorite(
            item: Self.favoriteItem(id: "favorite-1", sourceID: "source-1", favoritedAt: favoritedAt)
        )
        try favoriteRepository.restoreFavorite(
            item: Self.favoriteItem(id: "favorite-2", sourceID: "built-in.keep", favoritedAt: favoritedAt)
        )
        try libraryStates.save(
            UserLibraryState(
                userID: userID,
                selectedSourceID: "source-1",
                listContext: nil,
                lastRefreshAt: Date(timeIntervalSince1970: 90),
                updatedAt: Date(timeIntervalSince1970: 90)
            )
        )

        let receipt: SourceDeletionReceipt = try #require(try sourceRepository.deleteSource(id: "source-1"))

        #expect(try sourceRepository.fetchSources().map(\.id) == ["built-in.keep"])
        #expect(try comics.fetchHistory(userID: userID).map(\.sourceID) == ["built-in.keep"])
        #expect(try videos.fetchHistory(userID: userID).isEmpty)
        #expect(try books.fetchHistory(userID: userID).isEmpty)
        #expect(try favoriteRepository.fetchFavoriteItems().map(\.id) == ["favorite-2"])
        #expect(try favoriteRepository.fetchFavoriteItemIDs(sourceID: "source-1").isEmpty)
        #expect(try libraryStates.fetch(userID: userID)?.selectedSourceID == nil)
        // 中文注释：队列里是来源的删除、favorite-1 的删除（覆盖了收藏时的更新），加上 favorite-2 收藏时留下的更新。
        let favoriteEntityID: String = FavoriteItemIdentity(sourceID: "source-1", itemID: "favorite-1").syncEntityID
        let keptFavoriteEntityID: String = FavoriteItemIdentity(sourceID: "built-in.keep", itemID: "favorite-2").syncEntityID
        var pending: [SyncQueueItem] = try queueRepository.fetchPending(limit: 10)
        #expect(pending.count == 3)
        #expect(pending.first { $0.entityType == .source }?.operation == .delete)
        #expect(pending.first { $0.entityID == favoriteEntityID }?.operation == .delete)
        #expect(pending.first { $0.entityID == keptFavoriteEntityID }?.operation == .upsert)
        // 中文注释：留底里是被删的全部内容，供撤销写回。
        #expect(receipt.source.id == "source-1")
        #expect(receipt.source.enabled)
        #expect(receipt.librarySelection?.selectedSourceID == "source-1")
        #expect(receipt.comicHistories.count == 2)
        #expect(receipt.videoHistories.count == 1)
        #expect(receipt.bookHistories.count == 1)
        #expect(receipt.favoriteItems.map(\.id) == ["favorite-1"])
        #expect(receipt.enqueuedSyncChanges)

        try sourceRepository.restoreDeletedSource(receipt)

        let restoredSource: Source = try #require(try sourceRepository.fetchSources().first { $0.id == "source-1" })
        #expect(restoredSource.enabled)
        #expect(restoredSource.deletedAt == nil)
        let restoredChapters: [ComicChapterHistory] = try comics.fetchHistory(userID: userID)
            .filter { $0.sourceID == "source-1" }
            .sorted { $0.visitedAt < $1.visitedAt }
        #expect(restoredChapters.map(\.chapterKey) == [chapter1.chapterKey, chapter2.chapterKey])
        #expect(restoredChapters.map(\.lastPageIndex) == [4, 17])
        #expect(abs((restoredChapters.last?.visitedAt ?? .distantPast).timeIntervalSince(chapter2.visitedAt)) < 0.001)
        #expect(try videos.fetchHistory(userID: userID).map(\.sourceID) == ["source-1"])
        #expect(try books.fetchHistory(userID: userID).map(\.sourceID) == ["source-1"])
        let restoredFavorites: [FavoriteContentItem] = try favoriteRepository.fetchFavoriteItems()
        #expect(Set(restoredFavorites.map(\.id)) == ["favorite-1", "favorite-2"])
        let restoredFavorite: FavoriteContentItem = try #require(restoredFavorites.first { $0.id == "favorite-1" })
        #expect(abs((restoredFavorite.favoritedAt ?? .distantPast).timeIntervalSince(favoritedAt)) < 0.001)
        #expect(try libraryStates.fetch(userID: userID)?.selectedSourceID == "source-1")
        pending = try queueRepository.fetchPending(limit: 10)
        #expect(pending.count == 3)
        #expect(pending.first { $0.entityType == .source }?.operation == .upsert)
        #expect(pending.first { $0.entityID == favoriteEntityID }?.operation == .upsert)
    }

    // 中文注释：内置来源同样连带删除历史与收藏；它本身不入队，但收藏删除标记照常入队（否则其他设备会把收藏同步回来）。
    @Test func sourceRepositoryCascadesBuiltInSourceWithoutEnqueueingTheSource() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        let queueRepository: GRDBSyncQueueRepository = GRDBSyncQueueRepository(database: database)
        let comics: GRDBComicChapterHistoryRepository = GRDBComicChapterHistoryRepository(database: database)
        let userID: String = AppUser.localDefaultID

        try sourceRepository.saveSource(Self.makePluginSource(id: "built-in.comic"))
        try sourceRepository.saveSource(Self.makePluginSource(id: "built-in.empty"))
        try comics.save(Self.comicHistory(sourceID: "built-in.comic", chapter: 1))
        try favoriteRepository.restoreFavorite(
            item: Self.favoriteItem(id: "favorite-1", sourceID: "built-in.comic", favoritedAt: Date(timeIntervalSince1970: 60))
        )

        let receipt: SourceDeletionReceipt = try #require(try sourceRepository.deleteSource(id: "built-in.comic"))
        let emptyReceipt: SourceDeletionReceipt = try #require(try sourceRepository.deleteSource(id: "built-in.empty"))

        #expect(try comics.fetchHistory(userID: userID).isEmpty)
        #expect(try favoriteRepository.fetchFavoriteItems().isEmpty)
        let pending: [SyncQueueItem] = try queueRepository.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending.first?.entityType == .favoriteItem)
        #expect(pending.first?.operation == .delete)
        #expect(receipt.enqueuedSyncChanges)
        #expect(emptyReceipt.enqueuedSyncChanges == false)
    }

    private static func makeDatabase() throws -> AppDatabase {
        let path: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftTests-\(UUID().uuidString).sqlite")
            .path
        let database: AppDatabase = try AppDatabase(path: path)
        try database.queue.write { database in
            try AppUserRecord.insertLocalDefaultUser(in: database)
        }
        return database
    }

    private static func makePluginSource(id: String) -> Source {
        let now: Date = Date(timeIntervalSince1970: 100)
        return Source(
            id: id,
            name: "Example Source",
            baseURL: "https://example.test",
            type: .html,
            configuration: TestSourceFixtures.pluginConfiguration(),
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func favoriteItem() -> FavoriteContentItem {
        return FavoriteContentItem(
            id: "favorite-1",
            sourceID: "source-1",
            title: "Favorite Item",
            detailURL: "https://example.test/item/1",
            coverURL: nil,
            kind: .comic,
            latestText: nil,
            updatedAt: Date(timeIntervalSince1970: 100),
            favoritedAt: nil,
            listOrder: nil,
            listContext: nil,
            sourceSnapshot: nil
        )
    }

    private static func favoriteItem(id: String, sourceID: String, favoritedAt: Date) -> FavoriteContentItem {
        var item: FavoriteContentItem = Self.favoriteItem()
        item.id = id
        item.sourceID = sourceID
        item.detailURL = "https://example.test/item/\(id)"
        item.favoritedAt = favoritedAt
        return item
    }

    private static func comicHistory(sourceID: String, chapter: Int, pageIndex: Int? = nil) -> ComicChapterHistory {
        let detailURL: URL = URL(string: "https://example.test/comic/dragon")!
        return ComicChapterHistory(
            userID: AppUser.localDefaultID,
            sourceID: sourceID,
            comicItemID: "dragon",
            comicTitle: "Dragon",
            chapterID: "chapter-\(chapter)",
            chapterKey: "chapter-\(chapter)",
            chapterURL: detailURL.appendingPathComponent("chapter-\(chapter)"),
            chapterTitle: "#\(chapter)",
            visitedAt: Date(timeIntervalSince1970: 100 + TimeInterval(chapter)),
            coverURL: nil,
            lastPageIndex: pageIndex,
            sourceSnapshot: nil
        )
    }

    private static func videoHistory(sourceID: String) -> VideoWatchHistory {
        let detailURL: URL = URL(string: "https://example.test/video/show")!
        let visitedAt: Date = Date(timeIntervalSince1970: 100)
        return VideoWatchHistory(
            userID: AppUser.localDefaultID,
            sourceID: sourceID,
            vodID: "show",
            videoTitle: "Show",
            episodeTitle: "Episode 1",
            episodeKey: "episode-1",
            sourceIndex: 0,
            episodeIndex: 0,
            detailURL: detailURL,
            playPageURL: detailURL.appendingPathComponent("episode-1"),
            candidateMediaKind: .unknown,
            playbackStatus: .pageOnly,
            coverURL: nil,
            sourceName: "Example",
            lastPlaybackTime: 30,
            duration: 600,
            visitedAt: visitedAt,
            updatedAt: visitedAt
        )
    }

    private static func bookHistory(sourceID: String) -> BookReadingHistory {
        return BookReadingHistory(
            userID: AppUser.localDefaultID,
            sourceID: sourceID,
            detailURL: "https://example.test/book",
            bookItemID: "https://example.test/book",
            bookTitle: "Book",
            coverURL: nil,
            chapterTitle: "Chapter 1",
            chapterURL: nil,
            visitedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private static func sourceRecord(
        userID: String,
        id: String,
        updatedAt: Date,
        deletedAt: Date?
    ) -> SourceRecord {
        return SourceRecord(
            userID: userID,
            id: id,
            name: id,
            baseURL: "https://example.test",
            type: SourceType.html.rawValue,
            kind: SourceRuntimeKind.comic.rawValue,
            configJSON: "{}",
            enabled: true,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}
