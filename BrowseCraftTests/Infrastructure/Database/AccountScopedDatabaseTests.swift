import Foundation
import GRDB
import Testing
import BrowseCraftCore
@testable import BrowseCraft

struct AccountScopedDatabaseTests {
    @Test func appDatabaseDoesNotSeedLegacyUser() throws {
        let path: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftFinalSchemaTests-\(UUID().uuidString).sqlite")
            .path
        let database: AppDatabase = try AppDatabase(path: path)

        let userIDs: [String] = try database.queue.read { database in
            return try String.fetchAll(
                database,
                sql: "SELECT id FROM \(AppUserRecord.databaseTableName)"
            )
        }

        #expect(userIDs.isEmpty)
    }

    @Test func favoriteQueueIdentityRoundTripsUnicodeAndURLValues() {
        let identity: FavoriteItemIdentity = FavoriteItemIdentity(
            sourceID: "来源/🧭",
            itemID: "https://example.test/文章?id=同一个-guid"
        )

        #expect(FavoriteItemIdentity(syncEntityID: identity.syncEntityID) == identity)
    }

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

    @Test func freshDatabaseUsesSourceScopedFavoritePrimaryKey() throws {
        let database: AppDatabase = try Self.makeDatabase()

        let primaryKeyColumns: [String] = try database.queue.read { database in
            let rows: [Row] = try Row.fetchAll(database, sql: "PRAGMA table_info(favorite_items)")
            return rows.compactMap { row -> (position: Int, name: String)? in
                let position: Int = row["pk"]
                let name: String = row["name"]
                guard position > 0 else {
                    return nil
                }
                return (position, name)
            }
            .sorted { $0.position < $1.position }
            .map(\.name)
        }

        #expect(primaryKeyColumns == ["userID", "sourceID", "itemID"])
    }

    @Test func repositoriesKeepBusinessOwnerStableWhenCloudAccountChanges() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let activeScope: ActiveAccountScopeStore = ActiveAccountScopeStore()
        let activeUser: ActiveAppUserStore = Self.makeActiveUser()
        let repository: GRDBSourceRepository = GRDBSourceRepository(
            database: database,
            activeAppUser: activeUser,
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
        #expect(try repository.fetchSources().map(\.name) == ["Account B"])
    }

    @Test func identityAdoptionCopiesBusinessDataButNeverStoreKitRights() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let localUserID: UUID = UUID(
            uuidString: "7125df34-6803-47ef-af12-4ae763b1b806"
        )!
        let cloudUserID: UUID = UUID(
            uuidString: "e3aed9d8-0bbf-421c-a725-fb3ec8c86031"
        )!
        let timestamp: Date = Date(timeIntervalSince1970: 100)

        try database.queue.write { database in
            try AppUserRecord.insertUser(id: localUserID.uuidString, in: database)
            try database.execute(
                sql: """
                UPDATE \(AppUserRecord.databaseTableName)
                SET hasRemovedAds = 1,
                    siteSlotLimit = 47,
                    purchasedSiteSlots = 46,
                    lastStoreKitTransactionID = 'transaction-a'
                WHERE id = ?
                """,
                arguments: [localUserID.uuidString]
            )

            var sourceRecord: SourceRecord = try SourceRecord(
                source: Source(
                    userID: localUserID.uuidString,
                    id: "source-a",
                    name: "Local A",
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
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            )
            try sourceRecord.insert(database)
            try database.execute(
                sql: """
                INSERT INTO \(UserStoreKitTransactionRecord.databaseTableName)
                    (
                        userID,
                        transactionID,
                        originalTransactionID,
                        productID,
                        productType,
                        environment,
                        ownershipType,
                        purchaseDate,
                        createdAt
                    )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    localUserID.uuidString,
                    "transaction-a",
                    "original-a",
                    "com.example.slot",
                    "nonConsumable",
                    "Sandbox",
                    "purchased",
                    timestamp,
                    timestamp
                ]
            )
        }

        let adoptionStore: GRDBAppUserIdentityAdoptionStore =
            GRDBAppUserIdentityAdoptionStore(database: database)
        let summary: AppUserIdentityLocalDataSummary = try adoptionStore.summary(
            for: localUserID
        )
        let result: AppUserIdentityAdoptionResult = try adoptionStore
            .prepareAdoption(
                from: localUserID,
                to: cloudUserID,
                decision: .mergeLocalData
            )

        let cloudUser: AppUserRecord? = try database.queue.read { database in
            return try AppUserRecord.fetchOne(database, key: cloudUserID.uuidString)
        }
        let cloudSourceCount: Int = try database.queue.read { database in
            return try SourceRecord
                .filter(SourceRecord.Columns.userID == cloudUserID.uuidString)
                .fetchCount(database)
        }
        let localSourceCount: Int = try database.queue.read { database in
            return try SourceRecord
                .filter(SourceRecord.Columns.userID == localUserID.uuidString)
                .fetchCount(database)
        }
        let cloudTransactionCount: Int = try database.queue.read { database in
            return try UserStoreKitTransactionRecord
                .filter(
                    UserStoreKitTransactionRecord.Columns.userID ==
                        cloudUserID.uuidString
                )
                .fetchCount(database)
        }

        #expect(summary.sourceCount == 1)
        #expect(summary.hasMergeableData)
        #expect(result.copiedSourceCount == 1)
        #expect(cloudSourceCount == 1)
        #expect(localSourceCount == 1)
        #expect(cloudTransactionCount == 0)
        #expect(cloudUser?.hasRemovedAds == false)
        #expect(cloudUser?.siteSlotLimit == 1)
        #expect(cloudUser?.purchasedSiteSlots == 0)
        #expect(cloudUser?.lastStoreKitTransactionID == nil)
    }

    @Test func repositoryReadsTheCurrentActiveBusinessUserAtOperationTime() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let firstUser: UUID = UUID(uuidString: "7125df34-6803-47ef-af12-4ae763b1b806")!
        let secondUser: UUID = UUID(uuidString: "e3aed9d8-0bbf-421c-a725-fb3ec8c86031")!
        let activeUser: ActiveAppUserStore = ActiveAppUserStore(initialUserID: firstUser)
        let repository: GRDBSourceRepository = GRDBSourceRepository(
            database: database,
            activeAppUser: activeUser
        )

        try repository.saveSource(Self.makeSource(id: "shared-id", name: "First User"))
        activeUser.update(secondUser)
        try repository.saveSource(Self.makeSource(id: "shared-id", name: "Second User"))

        #expect(try repository.fetchSources().map(\.name) == ["Second User"])
        activeUser.update(firstUser)
        #expect(try repository.fetchSources().map(\.name) == ["First User"])
    }

    @Test func cloudAssociationAttestationIsScopedToTheConfirmedBusinessUser() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let firstUser: UUID = UUID(
            uuidString: "7125df34-6803-47ef-af12-4ae763b1b806"
        )!
        let secondUser: UUID = UUID(
            uuidString: "e3aed9d8-0bbf-421c-a725-fb3ec8c86031"
        )!
        let cloudScope: CloudAccountScope = .cloud(hash: "account-a")
        let activeUser: ActiveAppUserStore = ActiveAppUserStore(
            initialUserID: firstUser
        )
        try database.queue.write { database in
            try AppUserRecord.insertUser(id: firstUser.uuidString, in: database)
            try AppUserRecord.insertUser(id: secondUser.uuidString, in: database)
        }
        let store: GRDBCloudAccountPartitionStore =
            GRDBCloudAccountPartitionStore(
                database: database,
                activeAppUser: activeUser
            )

        try store.attestAssociation(
            cloudScope: cloudScope,
            userID: firstUser
        )
        _ = try store.prepareCloudScope(
            cloudScope,
            decision: .mergeLocalData
        )
        #expect(try store.associatedUserID(for: cloudScope) == firstUser)
        #expect(try store.preparation(for: cloudScope) != nil)

        activeUser.update(secondUser)
        #expect(try store.associatedUserID(for: cloudScope) == firstUser)
        #expect(try store.preparation(for: cloudScope) == nil)

        try store.attestAssociation(
            cloudScope: cloudScope,
            userID: secondUser
        )
        #expect(try store.associatedUserID(for: cloudScope) == secondUser)
    }

    @Test func syncCommitKeepsTheUserPinnedAtRunStart() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let firstUser: UUID = UUID(
            uuidString: "7125df34-6803-47ef-af12-4ae763b1b806"
        )!
        let secondUser: UUID = UUID(
            uuidString: "e3aed9d8-0bbf-421c-a725-fb3ec8c86031"
        )!
        try database.queue.write { database in
            try AppUserRecord.insertUser(id: firstUser.uuidString, in: database)
            try AppUserRecord.insertUser(id: secondUser.uuidString, in: database)
        }
        let activeUser: ActiveAppUserStore = ActiveAppUserStore(
            initialUserID: firstUser
        )
        let userContext: CloudSyncUserContext = CloudSyncUserContext()
        let localStore: GRDBSourceSyncLocalStore =
            GRDBSourceSyncLocalStore(
                database: database,
                activeAppUser: activeUser,
                userContext: userContext
            )
        userContext.begin(userID: firstUser)
        activeUser.update(secondUser)
        let timestamp: Date = Date(timeIntervalSince1970: 100)

        try localStore.commit(
            SourceSyncMergePlan(
                acceptedPayloads: [
                    SourceCloudPayload(
                        schemaVersion: SourceCloudPayload.currentSchemaVersion,
                        userID: secondUser.uuidString,
                        sourceID: "source-a",
                        name: "Pinned Source",
                        baseURL: "https://example.test",
                        type: SourceType.rss.rawValue,
                        kind: SourceRuntimeKind.rss.rawValue,
                        configJSON: "{}",
                        enabled: true,
                        createdAt: timestamp,
                        updatedAt: timestamp,
                        deletedAt: nil
                    )
                ],
                requeuedLocalChanges: [],
                changeToken: nil
            ),
            accountScope: .cloud(hash: "account-a"),
            scope: "private",
            zoneName: "BrowseCraftSync"
        )

        let firstUserCount: Int = try database.queue.read { database in
            try SourceRecord
                .filter(SourceRecord.Columns.userID == firstUser.uuidString)
                .fetchCount(database)
        }
        let secondUserCount: Int = try database.queue.read { database in
            try SourceRecord
                .filter(SourceRecord.Columns.userID == secondUser.uuidString)
                .fetchCount(database)
        }
        #expect(firstUserCount == 1)
        #expect(secondUserCount == 0)
    }

    @Test func favoritesWithSameItemIDRemainIsolatedBySource() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let repository: GRDBFavoriteRepository = GRDBFavoriteRepository(database: database)
        let first: FavoriteContentItem = Self.makeFavorite(
            sourceID: "source-a",
            title: "Source A"
        )
        let second: FavoriteContentItem = Self.makeFavorite(
            sourceID: "source-b",
            title: "Source B"
        )

        try repository.setFavorite(item: first, isFavorite: true)
        try repository.setFavorite(item: second, isFavorite: true)

        #expect(Set(try repository.fetchFavoriteItems().map(\.identity)) == [
            first.identity,
            second.identity
        ])
        #expect(try repository.fetchFavoriteItemIDs(sourceID: "source-a") == [first.id])
        #expect(try repository.fetchFavoriteItemIDs(sourceID: "source-b") == [second.id])

        let queueEntityIDs: Set<String> = Set(
            try GRDBSyncQueueRepository(database: database)
                .fetchPending(limit: 10)
                .map(\.entityID)
        )
        #expect(queueEntityIDs == [
            first.identity.syncEntityID,
            second.identity.syncEntityID
        ])

        try repository.setFavorite(item: first, isFavorite: false)

        #expect(try repository.fetchFavoriteItems().map(\.identity) == [second.identity])
    }

    @Test func mergeCopiesLocalDataAndKeepsOriginalSpace() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let localScope: ActiveAccountScopeStore = ActiveAccountScopeStore()
        let activeUser: ActiveAppUserStore = Self.makeActiveUser()
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(
            database: database,
            activeAppUser: activeUser,
            accountScopeProvider: localScope
        )
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(
            database: database,
            activeAppUser: activeUser,
            accountScopeProvider: localScope
        )
        let partitionStore: GRDBCloudAccountPartitionStore = GRDBCloudAccountPartitionStore(
            database: database,
            activeAppUser: activeUser
        )
        let cloudScope: CloudAccountScope = .cloud(hash: "account-a")

        try sourceRepository.saveSource(Self.makeSource(id: "source-1", name: "Local Source"))
        try favoriteRepository.setFavorite(item: Self.makeFavorite(), isFavorite: true)

        #expect(try partitionStore.preparation(for: cloudScope) == nil)
        let summary: CloudAccountPartitionSummary = try partitionStore.currentUserSummary()
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
        let activeUser: ActiveAppUserStore = Self.makeActiveUser()
        let repository: GRDBSourceRepository = GRDBSourceRepository(
            database: database,
            activeAppUser: activeUser,
            accountScopeProvider: activeScope
        )
        let partitionStore: GRDBCloudAccountPartitionStore = GRDBCloudAccountPartitionStore(
            database: database,
            activeAppUser: activeUser
        )
        let cloudScope: CloudAccountScope = .cloud(hash: "account-a")

        try repository.saveSource(Self.makeSource(id: "source-1", name: "First Local Source"))
        _ = try partitionStore.prepareCloudScope(cloudScope, decision: .mergeLocalData)
        try database.queue.write { database in
            try database.execute(
                sql: """
                UPDATE \(AppUserRecord.databaseTableName)
                SET siteSlotLimit = 2,
                    purchasedSiteSlots = 1
                WHERE id = ?
                """,
                arguments: [activeUser.currentUserID.uuidString]
            )
        }
        try repository.saveSource(Self.makeSource(id: "source-2", name: "Later Local Source"))

        let repeatedResult: CloudAccountPartitionMergeResult = try partitionStore.prepareCloudScope(
            cloudScope,
            decision: .mergeLocalData
        )

        #expect(repeatedResult.wasAlreadyPrepared)
        #expect(repeatedResult.copiedSourceCount == 0)
        #expect(repeatedResult.copiedFavoriteItemCount == 0)
        activeScope.update(cloudScope)
        #expect(Set(try repository.fetchSources().map(\.id)) == ["source-1", "source-2"])
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

    @Test func useCloudDataOnlyClearsCurrentUsersCloudSyncedContent() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let localScope: ActiveAccountScopeStore = ActiveAccountScopeStore()
        let activeUser: ActiveAppUserStore = Self.makeActiveUser()
        let repository: GRDBSourceRepository = GRDBSourceRepository(
            database: database,
            activeAppUser: activeUser,
            accountScopeProvider: localScope
        )
        let partitionStore: GRDBCloudAccountPartitionStore = GRDBCloudAccountPartitionStore(
            database: database,
            activeAppUser: activeUser
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
        #expect(try repository.fetchSources().isEmpty)
    }

    @Test func favoriteQueueAndSyncStateAreIsolatedByAccount() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let activeScope: ActiveAccountScopeStore = ActiveAccountScopeStore()
        let activeUser: ActiveAppUserStore = Self.makeActiveUser()
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(
            database: database,
            activeAppUser: activeUser,
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
        #expect(try favoriteRepository.fetchFavoriteItems().map(\.title) == ["Account B"])
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
        let database: AppDatabase = try AppDatabase(path: path)
        try database.queue.write { database in
            try AppUserRecord.insertLocalDefaultUser(in: database)
        }
        return database
    }

    private static func makeActiveUser() -> ActiveAppUserStore {
        return ActiveAppUserStore(
            initialUserID: UUID(uuidString: "7125df34-6803-47ef-af12-4ae763b1b806")!
        )
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

    private static func makeFavorite(
        sourceID: String = "source-1",
        title: String = "Favorite"
    ) -> FavoriteContentItem {
        return FavoriteContentItem(
            id: "favorite-1",
            sourceID: sourceID,
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
