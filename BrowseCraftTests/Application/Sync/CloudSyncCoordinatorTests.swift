import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

struct CloudSyncCoordinatorTests {
    @Test func manualSyncDownloadsBothTypesBeforeUploadingEitherQueue() async throws {
        let database: AppDatabase = try Self.makeDatabase()
        let accountScope: CloudAccountScope = .cloud(hash: "account-a")
        let activeScope: ActiveAccountScopeStore = ActiveAccountScopeStore()
        let stateProvider: MockCloudAccountStateProvider = MockCloudAccountStateProvider(
            state: CloudAccountState(availability: .available, scope: accountScope)
        )
        let preferences: MockCloudSyncPreferenceStore = MockCloudSyncPreferenceStore()
        preferences.setCloudSyncEnabled(true, for: accountScope)
        let session: CloudAccountSession = CloudAccountSession(
            stateProvider: stateProvider,
            preferenceStore: preferences,
            activeScopeStore: activeScope
        )
        await session.start()

        let cloudStore: MockCloudRecordStore = MockCloudRecordStore()
        let notifier: CloudSyncChangeNotifier = CloudSyncChangeNotifier()
        let sourceRepository: GRDBSourceRepository = GRDBSourceRepository(
            database: database,
            accountScopeProvider: activeScope
        )
        let favoriteRepository: GRDBFavoriteRepository = GRDBFavoriteRepository(
            database: database,
            accountScopeProvider: activeScope
        )
        try sourceRepository.saveSource(Self.makeSource())
        try favoriteRepository.setFavorite(item: Self.makeFavorite(), isFavorite: true)

        let coordinator: CloudSyncCoordinator = CloudSyncCoordinator(
            accountSession: session,
            sourceService: SourceSyncService(
                localStore: GRDBSourceSyncLocalStore(database: database),
                cloudStore: cloudStore,
                accountScopeProvider: activeScope
            ),
            favoriteItemService: FavoriteItemSyncService(
                localStore: GRDBFavoriteItemSyncLocalStore(database: database),
                cloudStore: cloudStore,
                accountScopeProvider: activeScope
            ),
            cloudStore: cloudStore,
            changeNotifier: notifier
        )

        let result: CloudSyncRunResult = try await coordinator.synchronize(trigger: .manual)

        #expect(cloudStore.events() == ["sourceFetch", "favoriteFetch", "sourceSave", "favoriteSave"])
        #expect(result.uploadedCount == 2)
        #expect(result.failedCount == 0)
    }

    private static func makeDatabase() throws -> AppDatabase {
        let path: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftCoordinatorTests-\(UUID().uuidString).sqlite")
            .path
        return try AppDatabase(path: path)
    }

    private static func makeSource() -> Source {
        let now: Date = Date(timeIntervalSince1970: 100)
        return Source(
            id: "source-1",
            name: "Source",
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

    private static func makeFavorite() -> FavoriteContentItem {
        return FavoriteContentItem(
            id: "favorite-1",
            sourceID: "source-1",
            title: "Favorite",
            detailURL: "https://example.test/item",
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
