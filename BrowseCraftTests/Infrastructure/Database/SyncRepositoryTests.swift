import Foundation
import Testing
import GRDB
import BrowseCraftCore
@testable import BrowseCraft

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
            try AppUserRecord.insertUser(id: accountScope.rawValue, in: database)
            var activeSource: SourceRecord = Self.sourceRecord(
                userID: accountScope.rawValue,
                id: "source-active",
                updatedAt: changedAt,
                deletedAt: nil
            )
            try activeSource.insert(database)
            var deletedSource: SourceRecord = Self.sourceRecord(
                userID: accountScope.rawValue,
                id: "source-deleted",
                updatedAt: changedAt,
                deletedAt: changedAt
            )
            try deletedSource.insert(database)
            var builtInSource: SourceRecord = Self.sourceRecord(
                userID: accountScope.rawValue,
                id: "built-in.rss.example",
                updatedAt: changedAt,
                deletedAt: nil
            )
            try builtInSource.insert(database)

            var activeFavorite: FavoriteItemRecord = try FavoriteItemRecord(
                userID: accountScope.rawValue,
                item: Self.favoriteItem(),
                updatedAt: changedAt,
                deletedAt: nil
            )
            try activeFavorite.insert(database)
            var deletedFavorite: FavoriteItemRecord = try FavoriteItemRecord(
                userID: accountScope.rawValue,
                item: FavoriteContentItem(
                    id: "favorite-deleted",
                    sourceID: "source-active",
                    title: "Deleted",
                    detailURL: "https://example.test/deleted",
                    coverURL: nil,
                    kind: .rss,
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
            try AppUserRecord.insertUser(id: accountScope.rawValue, in: database)
            var source: SourceRecord = Self.sourceRecord(
                userID: accountScope.rawValue,
                id: "source-active",
                updatedAt: changedAt,
                deletedAt: nil
            )
            try source.insert(database)
            var favorite: FavoriteItemRecord = try FavoriteItemRecord(
                userID: accountScope.rawValue,
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
                    .filter(SourceRecord.Columns.userID == accountScope.rawValue)
                    .fetchCount(database),
                favorites: try FavoriteItemRecord
                    .filter(FavoriteItemRecord.Columns.userID == accountScope.rawValue)
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
        let source: Source = Self.makeRSSSource(id: "user-source-1")

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

    private static func makeDatabase() throws -> AppDatabase {
        let path: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftTests-\(UUID().uuidString).sqlite")
            .path
        return try AppDatabase(path: path)
    }

    private static func makeRSSSource(id: String) -> Source {
        let now: Date = Date(timeIntervalSince1970: 100)
        return Source(
            id: id,
            name: "Example RSS",
            baseURL: "https://example.test",
            type: .rss,
            configuration: .rss(
                RSSSourceConfiguration(
                    definition: RSSSourceDefinition(
                        feedURL: URL(string: "https://example.test/feed.xml") ?? URL(fileURLWithPath: "/"),
                        requiresAccount: false,
                        refreshPolicy: .manual
                    )
                )
            ),
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
            kind: .rss,
            latestText: nil,
            updatedAt: Date(timeIntervalSince1970: 100),
            favoritedAt: nil,
            listOrder: nil,
            listContext: nil,
            sourceSnapshot: nil
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
            type: SourceType.rss.rawValue,
            kind: SourceRuntimeKind.rss.rawValue,
            configJSON: "{}",
            enabled: true,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}
