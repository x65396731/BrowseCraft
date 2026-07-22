import Foundation
import GRDB
import Testing
import BrowseCraftCore
@testable import BrowseCraft

struct AccountScopedDatabaseTests {
    @Test func freshDatabaseHasAccountScopedSourceKeyAndValidForeignKeys() throws {
        let database: AppDatabase = try Self.makeDatabase()

        let primaryKeyColumns: [String] = try database.queue.read { database in
            let rows: [Row] = try Row.fetchAll(database, sql: "PRAGMA table_info(sources)")
            return rows.compactMap { row -> (position: Int, name: String)? in
                let position: Int = row["pk"]
                let name: String = row["name"]
                guard position > 0 else {
                    return nil
                }
                return (position, name)
            }
            .sorted { lhs, rhs in lhs.position < rhs.position }
            .map(\.name)
        }
        let foreignKeyViolationCount: Int = try database.queue.read { database in
            return try Row.fetchAll(database, sql: "PRAGMA foreign_key_check").count
        }

        #expect(primaryKeyColumns == ["userID", "id"])
        #expect(foreignKeyViolationCount == 0)
    }

    @Test func repositoriesKeepSameSourceIDIsolatedByAccount() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let activeScope: ActiveAccountScopeStore = ActiveAccountScopeStore()
        let repository: GRDBSourceRepository = GRDBSourceRepository(
            database: database,
            accountScopeProvider: activeScope
        )
        let accountA: CloudAccountScope = .cloud(hash: "account-a")
        let accountB: CloudAccountScope = .cloud(hash: "account-b")

        activeScope.update(accountA)
        try repository.saveSource(Self.makeSource(id: "shared-id", name: "Account A"))

        activeScope.update(accountB)
        try repository.saveSource(Self.makeSource(id: "shared-id", name: "Account B"))

        #expect(try repository.fetchSources().map(\.name) == ["Account B"])

        activeScope.update(accountA)
        #expect(try repository.fetchSources().map(\.name) == ["Account A"])
    }

    @Test func mergeCopiesLocalDataAndKeepsOriginalSpace() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let localScope: ActiveAccountScopeStore = ActiveAccountScopeStore()
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(
            database: database,
            accountScopeProvider: localScope
        )
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(
            database: database,
            accountScopeProvider: localScope
        )
        let partitionStore: GRDBCloudAccountPartitionStore = GRDBCloudAccountPartitionStore(
            database: database
        )
        let cloudScope: CloudAccountScope = .cloud(hash: "account-a")

        try sourceRepository.saveSource(Self.makeSource(id: "source-1", name: "Local Source"))
        try favoriteRepository.setFavorite(item: Self.makeFavorite(), isFavorite: true)

        #expect(try partitionStore.preparation(for: cloudScope) == nil)
        let summary: CloudAccountPartitionSummary = try partitionStore.localDefaultSummary()
        #expect(summary.sourceCount == 1)
        #expect(summary.favoriteItemCount == 1)

        let result: CloudAccountPartitionMergeResult = try partitionStore.prepareCloudScope(
            cloudScope,
            decision: .mergeLocalData
        )
        #expect(result.copiedSourceCount == 1)
        #expect(result.copiedFavoriteItemCount == 1)
        #expect(result.wasAlreadyPrepared == false)
        #expect(try partitionStore.preparation(for: cloudScope)?.decision == .mergeLocalData)
        #expect(try partitionStore.preparation(for: cloudScope)?.initialSyncCompletedAt == nil)

        let completedAt: Date = Date(timeIntervalSince1970: 200)
        try partitionStore.markInitialSyncCompleted(for: cloudScope, at: completedAt)
        try partitionStore.markInitialSyncCompleted(
            for: cloudScope,
            at: Date(timeIntervalSince1970: 300)
        )
        #expect(
            try partitionStore.preparation(for: cloudScope)?.initialSyncCompletedAt == completedAt
        )

        localScope.update(cloudScope)
        #expect(try sourceRepository.fetchSources().map(\.id) == ["source-1"])
        #expect(try favoriteRepository.fetchFavoriteItemIDs() == ["favorite-1"])

        let cloudQueue: [SyncQueueItem] = try GRDBSyncQueueRepository(
            database: database,
            accountScopeProvider: localScope
        ).fetchPending(limit: 10)
        #expect(cloudQueue.count == 2)
        #expect(cloudQueue.allSatisfy { $0.accountScope == cloudScope })

        localScope.update(.localDefault)
        #expect(try sourceRepository.fetchSources().map(\.id) == ["source-1"])
        #expect(try favoriteRepository.fetchFavoriteItemIDs() == ["favorite-1"])
    }

    @Test func repeatedPreparationIsIdempotentAndDoesNotCopyLaterLocalData() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let activeScope: ActiveAccountScopeStore = ActiveAccountScopeStore()
        let repository: GRDBSourceRepository = GRDBSourceRepository(
            database: database,
            accountScopeProvider: activeScope
        )
        let partitionStore: GRDBCloudAccountPartitionStore = GRDBCloudAccountPartitionStore(
            database: database
        )
        let cloudScope: CloudAccountScope = .cloud(hash: "account-a")

        try repository.saveSource(Self.makeSource(id: "source-1", name: "First Local Source"))
        _ = try partitionStore.prepareCloudScope(cloudScope, decision: .mergeLocalData)
        try repository.saveSource(Self.makeSource(id: "source-2", name: "Later Local Source"))

        let repeatedResult: CloudAccountPartitionMergeResult = try partitionStore.prepareCloudScope(
            cloudScope,
            decision: .mergeLocalData
        )

        #expect(repeatedResult.wasAlreadyPrepared)
        #expect(repeatedResult.copiedSourceCount == 0)
        #expect(repeatedResult.copiedFavoriteItemCount == 0)
        activeScope.update(cloudScope)
        #expect(try repository.fetchSources().map(\.id) == ["source-1"])
    }

    @Test func preparedCloudScopeRejectsAConflictingDecision() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let partitionStore: GRDBCloudAccountPartitionStore = GRDBCloudAccountPartitionStore(
            database: database
        )
        let cloudScope: CloudAccountScope = .cloud(hash: "account-a")

        _ = try partitionStore.prepareCloudScope(cloudScope, decision: .mergeLocalData)

        #expect(
            throws: CloudAccountPartitionError.alreadyPrepared(
                existingDecision: .mergeLocalData
            )
        ) {
            _ = try partitionStore.prepareCloudScope(
                cloudScope,
                decision: .useCloudDataOnly
            )
        }
    }

    @Test func useCloudDataOnlyDoesNotCopyOrDeleteLocalData() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let localScope: ActiveAccountScopeStore = ActiveAccountScopeStore()
        let repository: GRDBSourceRepository = GRDBSourceRepository(
            database: database,
            accountScopeProvider: localScope
        )
        let partitionStore: GRDBCloudAccountPartitionStore = GRDBCloudAccountPartitionStore(
            database: database
        )
        let cloudScope: CloudAccountScope = .cloud(hash: "account-a")

        try repository.saveSource(Self.makeSource(id: "source-1", name: "Local Source"))
        let result: CloudAccountPartitionMergeResult = try partitionStore.prepareCloudScope(
            cloudScope,
            decision: .useCloudDataOnly
        )

        #expect(result.wasAlreadyPrepared == false)
        #expect(try partitionStore.preparation(for: cloudScope)?.decision == .useCloudDataOnly)

        localScope.update(cloudScope)
        #expect(try repository.fetchSources().isEmpty)

        localScope.update(.localDefault)
        #expect(try repository.fetchSources().map(\.id) == ["source-1"])
    }

    @Test func favoriteQueueAndSyncStateAreIsolatedByAccount() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let activeScope: ActiveAccountScopeStore = ActiveAccountScopeStore()
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(
            database: database,
            accountScopeProvider: activeScope
        )
        let queueRepository: GRDBSyncQueueRepository = GRDBSyncQueueRepository(
            database: database,
            accountScopeProvider: activeScope
        )
        let stateRepository: GRDBSyncStateRepository = GRDBSyncStateRepository(
            database: database,
            accountScopeProvider: activeScope
        )
        let accountA: CloudAccountScope = .cloud(hash: "account-a")
        let accountB: CloudAccountScope = .cloud(hash: "account-b")
        let date: Date = Date(timeIntervalSince1970: 100)

        activeScope.update(accountA)
        try favoriteRepository.setFavorite(
            item: Self.makeFavorite(title: "Account A"),
            isFavorite: true
        )
        try queueRepository.enqueue(entityType: .source, entityID: "shared-id", operation: .upsert)
        try stateRepository.saveState(
            SyncState(
                scope: "private",
                zoneName: "BrowseCraft",
                serverChangeTokenData: Data([0x0A]),
                lastSyncedAt: date,
                updatedAt: date
            )
        )

        activeScope.update(accountB)
        try favoriteRepository.setFavorite(
            item: Self.makeFavorite(title: "Account B"),
            isFavorite: true
        )
        try queueRepository.enqueue(entityType: .source, entityID: "shared-id", operation: .delete)
        try stateRepository.saveState(
            SyncState(
                scope: "private",
                zoneName: "BrowseCraft",
                serverChangeTokenData: Data([0x0B]),
                lastSyncedAt: date,
                updatedAt: date
            )
        )

        #expect(try favoriteRepository.fetchFavoriteItems().map(\.title) == ["Account B"])
        #expect(
            try queueRepository.fetchPending(limit: 10)
                .first { $0.entityType == .source }?
                .operation == .delete
        )
        #expect(try stateRepository.fetchState(scope: "private", zoneName: "BrowseCraft")?.serverChangeTokenData == Data([0x0B]))

        activeScope.update(accountA)
        #expect(try favoriteRepository.fetchFavoriteItems().map(\.title) == ["Account A"])
        #expect(
            try queueRepository.fetchPending(limit: 10)
                .first { $0.entityType == .source }?
                .operation == .upsert
        )
        #expect(try stateRepository.fetchState(scope: "private", zoneName: "BrowseCraft")?.serverChangeTokenData == Data([0x0A]))
    }

    private static func makeDatabase() throws -> AppDatabase {
        let path: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftAccountScopeTests-\(UUID().uuidString).sqlite")
            .path
        return try AppDatabase(path: path)
    }

    private static func makeSource(id: String, name: String) -> Source {
        let now: Date = Date(timeIntervalSince1970: 100)
        return Source(
            id: id,
            name: name,
            baseURL: "https://example.test",
            type: .rss,
            configuration: .rss(
                RSSSourceConfiguration(
                    definition: RSSSourceDefinition(
                        feedURL: URL(string: "https://example.test/feed.xml")!,
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

    private static func makeFavorite(title: String = "Favorite") -> FavoriteContentItem {
        return FavoriteContentItem(
            id: "favorite-1",
            sourceID: "source-1",
            title: title,
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
