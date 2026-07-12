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
        try repository.markFailed(id: "source:source-1", errorMessage: "Network unavailable")

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

        try repository.markSynced(id: "source:source-1")
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
            let record: SourceRecord? = try SourceRecord.fetchOne(database, key: "user-source-1")
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
        #expect(pending[0].entityID == "favorite-1")
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
}
