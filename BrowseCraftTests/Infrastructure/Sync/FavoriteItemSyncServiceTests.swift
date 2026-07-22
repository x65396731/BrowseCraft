import Foundation
import Testing
import GRDB
@testable import BrowseCraft

struct FavoriteItemSyncServiceTests {
    @Test func uploadsLocalFavoriteItemAndClearsQueue() async throws {
        let database: AppDatabase = try Self.makeDatabase()
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        let queueRepository: GRDBSyncQueueRepository = GRDBSyncQueueRepository(database: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        let service: FavoriteItemSyncService = Self.makeService(database: database, cloudStore: cloudStore)

        try favoriteRepository.setFavorite(item: Self.favoriteItem(id: "favorite-1"), isFavorite: true)

        let result: FavoriteItemSyncResult = try await service.syncFavoriteItems(limit: 10)

        #expect(result.uploadedCount == 1)
        #expect(cloudStore.favoriteItemRecord(id: "favorite-1")?.payload.title == "Favorite 1")
        #expect(try queueRepository.fetchPending(limit: 10).isEmpty)
    }

    @Test func drainsFavoriteQueueAcrossMultipleBatches() async throws {
        let database: AppDatabase = try Self.makeDatabase()
        let queueRepository: GRDBSyncQueueRepository = GRDBSyncQueueRepository(database: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        let service: FavoriteItemSyncService = Self.makeService(
            database: database,
            cloudStore: cloudStore
        )

        try await database.queue.write { database in
            for index: Int in 0..<205 {
                let item: FavoriteContentItem = Self.favoriteItem(id: "favorite-\(index)")
                var record: FavoriteItemRecord = try FavoriteItemRecord(
                    userID: AppUser.localDefaultID,
                    item: item,
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(100 + index)),
                    deletedAt: nil
                )
                try record.save(database)
                try SyncQueueRecord.enqueue(
                    accountScope: .localDefault,
                    entityType: .favoriteItem,
                    entityID: item.identity.syncEntityID,
                    operation: .upsert,
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(100 + index)),
                    in: database
                )
            }
        }

        let result: FavoriteItemSyncResult = try await service.syncFavoriteItems(limit: 100)

        #expect(result.uploadedCount == 205)
        #expect(try queueRepository.fetchPending(limit: 300).isEmpty)
        #expect(cloudStore.events().filter { $0 == "favoriteSave" }.count == 3)
    }

    @Test func uploadsSameItemIDFromDifferentSourcesAsDistinctRecords() async throws {
        let database: AppDatabase = try Self.makeDatabase()
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        let service: FavoriteItemSyncService = Self.makeService(
            database: database,
            cloudStore: cloudStore
        )
        let first: FavoriteContentItem = Self.favoriteItem(
            id: "shared-guid",
            sourceID: "source-a"
        )
        let second: FavoriteContentItem = Self.favoriteItem(
            id: "shared-guid",
            sourceID: "source-b"
        )

        try favoriteRepository.setFavorite(item: first, isFavorite: true)
        try favoriteRepository.setFavorite(item: second, isFavorite: true)

        let result: FavoriteItemSyncResult = try await service.syncFavoriteItems(limit: 10)

        #expect(result.uploadedCount == 2)
        #expect(cloudStore.favoriteItemRecord(sourceID: "source-a", itemID: "shared-guid") != nil)
        #expect(cloudStore.favoriteItemRecord(sourceID: "source-b", itemID: "shared-guid") != nil)
    }

    @Test func downloadsCloudFavoriteItemAndRebuildsAggregate() async throws {
        let database: AppDatabase = try Self.makeDatabase()
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore(
            favoriteItemRecords: [
                FavoriteItemCloudRecord(
                    payload: try Self.payload(id: "favorite-1", title: "Cloud Favorite", updatedAt: 100),
                    serverUpdatedAt: Date(timeIntervalSince1970: 110),
                    version: 1
                )
            ]
        )
        let service: FavoriteItemSyncService = Self.makeService(database: database, cloudStore: cloudStore)

        let result: FavoriteItemSyncResult = try await service.syncFavoriteItems(limit: 10)
        let items: [FavoriteContentItem] = try favoriteRepository.fetchFavoriteItems()

        #expect(result.downloadedCount == 1)
        #expect(items.map(\.id) == ["favorite-1"])
        #expect(items.first?.title == "Cloud Favorite")
    }

    @Test func uploadsCancelFavoriteAsTombstone() async throws {
        let database: AppDatabase = try Self.makeDatabase()
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        let service: FavoriteItemSyncService = Self.makeService(database: database, cloudStore: cloudStore)
        let item: FavoriteContentItem = Self.favoriteItem(id: "favorite-1")

        try favoriteRepository.setFavorite(item: item, isFavorite: true)
        try favoriteRepository.setFavorite(item: item, isFavorite: false)

        let result: FavoriteItemSyncResult = try await service.syncFavoriteItems(limit: 10)

        #expect(result.uploadedCount == 1)
        #expect(cloudStore.favoriteItemRecord(id: "favorite-1")?.payload.deletedAt != nil)
    }

    @Test func cloudTombstoneRemovesFavoriteFromAggregate() async throws {
        let database: AppDatabase = try Self.makeDatabase()
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        try Self.insertFavoriteItem(Self.favoriteItem(id: "favorite-1"), updatedAt: 100, into: database)
        try Self.clearSyncQueue(in: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore(
            favoriteItemRecords: [
                FavoriteItemCloudRecord(
                    payload: try Self.payload(
                        id: "favorite-1",
                        title: "Deleted Favorite",
                        updatedAt: 100,
                        deletedAt: 200
                    ),
                    serverUpdatedAt: Date(timeIntervalSince1970: 210),
                    version: 1
                )
            ]
        )
        let service: FavoriteItemSyncService = Self.makeService(database: database, cloudStore: cloudStore)

        let result: FavoriteItemSyncResult = try await service.syncFavoriteItems(limit: 10)

        #expect(result.deletedCount == 1)
        #expect(try favoriteRepository.fetchFavoriteItems().isEmpty)
    }

    @Test func newerLocalFavoriteWinsOverOlderCloudFavorite() async throws {
        let database: AppDatabase = try Self.makeDatabase()
        try Self.insertFavoriteItem(Self.favoriteItem(id: "favorite-1", title: "Local New"), updatedAt: 200, into: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore(
            favoriteItemRecords: [
                FavoriteItemCloudRecord(
                    payload: try Self.payload(id: "favorite-1", title: "Cloud Old", updatedAt: 100),
                    serverUpdatedAt: Date(timeIntervalSince1970: 110),
                    version: 1
                )
            ]
        )
        let service: FavoriteItemSyncService = Self.makeService(database: database, cloudStore: cloudStore)

        let result: FavoriteItemSyncResult = try await service.syncFavoriteItems(limit: 10)

        #expect(result.skippedCount == 1)
        #expect(result.uploadedCount == 1)
        #expect(cloudStore.favoriteItemRecord(id: "favorite-1")?.payload.title == "Local New")
    }

    @Test func newerCloudFavoriteWinsOverOlderLocalFavorite() async throws {
        let database: AppDatabase = try Self.makeDatabase()
        try Self.insertFavoriteItem(Self.favoriteItem(id: "favorite-1", title: "Local Old"), updatedAt: 100, into: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore(
            favoriteItemRecords: [
                FavoriteItemCloudRecord(
                    payload: try Self.payload(id: "favorite-1", title: "Cloud New", updatedAt: 200),
                    serverUpdatedAt: Date(timeIntervalSince1970: 210),
                    version: 1
                )
            ]
        )
        let service: FavoriteItemSyncService = Self.makeService(database: database, cloudStore: cloudStore)

        _ = try await service.syncFavoriteItems(limit: 10)
        let items: [FavoriteContentItem] = try GRDBFavoriteRepository(database: database).fetchFavoriteItems()

        #expect(items.first?.title == "Cloud New")
    }

    @Test func localTombstoneWinsWhenCloudFavoriteHasSameTimestamp() async throws {
        let database: AppDatabase = try Self.makeDatabase()
        try Self.insertFavoriteItem(
            Self.favoriteItem(id: "favorite-1", title: "Deleted Local"),
            updatedAt: 100,
            deletedAt: 200,
            into: database
        )
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore(
            favoriteItemRecords: [
                FavoriteItemCloudRecord(
                    payload: try Self.payload(
                        id: "favorite-1",
                        title: "Cloud Live",
                        updatedAt: 200
                    ),
                    serverUpdatedAt: Date(timeIntervalSince1970: 210),
                    version: 1
                )
            ]
        )
        let service: FavoriteItemSyncService = Self.makeService(database: database, cloudStore: cloudStore)

        let result: FavoriteItemSyncResult = try await service.syncFavoriteItems(limit: 10)

        #expect(result.skippedCount == 1)
        #expect(cloudStore.favoriteItemRecord(id: "favorite-1")?.payload.deletedAt != nil)
        #expect(try GRDBFavoriteRepository(database: database).fetchFavoriteItems().isEmpty)
    }

    @Test func uploadFailureKeepsFavoriteItemQueueAndIncrementsRetryCount() async throws {
        let database: AppDatabase = try Self.makeDatabase()
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        let queueRepository: GRDBSyncQueueRepository = GRDBSyncQueueRepository(database: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        cloudStore.failNextSave = true
        let service: FavoriteItemSyncService = Self.makeService(database: database, cloudStore: cloudStore)

        try favoriteRepository.setFavorite(item: Self.favoriteItem(id: "favorite-1"), isFavorite: true)

        await #expect(throws: MockCloudRecordStoreError.saveFailed) {
            _ = try await service.syncFavoriteItems(limit: 10)
        }
        let pending: [SyncQueueItem] = try queueRepository.fetchPending(limit: 10)

        #expect(pending.count == 1)
        #expect(pending[0].entityType == .favoriteItem)
        #expect(pending[0].retryCount == 1)
        #expect(pending[0].lastError != nil)
    }

    @Test func partialUploadRemovesOnlyConfirmedFavoriteQueueItems() async throws {
        let database: AppDatabase = try Self.makeDatabase()
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        let queueRepository: GRDBSyncQueueRepository = GRDBSyncQueueRepository(database: database)
        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        cloudStore.nextFavoriteItemSaveFailureIDs = ["favorite-2"]
        let service: FavoriteItemSyncService = Self.makeService(database: database, cloudStore: cloudStore)
        try favoriteRepository.setFavorite(item: Self.favoriteItem(id: "favorite-1"), isFavorite: true)
        try favoriteRepository.setFavorite(item: Self.favoriteItem(id: "favorite-2"), isFavorite: true)

        let result: FavoriteItemSyncResult = try await service.syncFavoriteItems(limit: 10)
        let pending: [SyncQueueItem] = try queueRepository.fetchPending(limit: 10)

        #expect(result.uploadedCount == 1)
        #expect(result.failedCount == 1)
        #expect(pending.map(\.entityID) == [
            FavoriteItemIdentity(sourceID: "source-1", itemID: "favorite-2").syncEntityID
        ])
        #expect(pending.first?.retryCount == 1)
        #expect(cloudStore.favoriteItemRecord(id: "favorite-1") != nil)
        #expect(cloudStore.favoriteItemRecord(id: "favorite-2") == nil)
    }

    private static func makeDatabase() throws -> AppDatabase {
        let path: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftFavoriteSyncTests-\(UUID().uuidString).sqlite")
            .path
        return try AppDatabase(path: path)
    }

    private static func makeService(
        database: AppDatabase,
        cloudStore: CloudRecordStore
    ) -> FavoriteItemSyncService {
        return FavoriteItemSyncService(
            localStore: GRDBFavoriteItemSyncLocalStore(database: database),
            cloudStore: cloudStore
        )
    }

    private static func insertFavoriteItem(
        _ item: FavoriteContentItem,
        updatedAt: TimeInterval,
        deletedAt: TimeInterval? = nil,
        into database: AppDatabase
    ) throws {
        try database.queue.write { database in
            var record: FavoriteItemRecord = try FavoriteItemRecord(
                userID: AppUser.localDefaultID,
                item: item,
                updatedAt: Date(timeIntervalSince1970: updatedAt),
                deletedAt: deletedAt.map(Date.init(timeIntervalSince1970:))
            )
            try record.save(database)
            try FavoriteAggregateBuilder.rebuild(userID: AppUser.localDefaultID, in: database)
            try SyncQueueRecord.enqueue(
                accountScope: .localDefault,
                entityType: .favoriteItem,
                entityID: item.identity.syncEntityID,
                operation: deletedAt == nil ? .upsert : .delete,
                updatedAt: Date(timeIntervalSince1970: updatedAt),
                in: database
            )
        }
    }

    private static func clearSyncQueue(in database: AppDatabase) throws {
        try database.queue.write { database in
            _ = try SyncQueueRecord.deleteAll(database)
        }
    }

    private static func payload(
        id: String,
        title: String,
        updatedAt: TimeInterval,
        deletedAt: TimeInterval? = nil
    ) throws -> FavoriteItemCloudPayload {
        let record: FavoriteItemRecord = try FavoriteItemRecord(
            userID: AppUser.localDefaultID,
            item: Self.favoriteItem(id: id, title: title),
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            deletedAt: deletedAt.map(Date.init(timeIntervalSince1970:))
        )
        return try FavoriteItemCloudPayload(record: record)
    }

    private static func favoriteItem(
        id: String,
        sourceID: String = "source-1",
        title: String? = nil
    ) -> FavoriteContentItem {
        return FavoriteContentItem(
            id: id,
            sourceID: sourceID,
            title: title ?? "Favorite \(id.suffix(1))",
            detailURL: "https://example.test/items/\(id)",
            coverURL: nil,
            kind: .rss,
            latestText: nil,
            updatedAt: Date(timeIntervalSince1970: 100),
            favoritedAt: Date(timeIntervalSince1970: 100),
            listOrder: nil,
            listContext: nil,
            sourceSnapshot: nil
        )
    }
}
