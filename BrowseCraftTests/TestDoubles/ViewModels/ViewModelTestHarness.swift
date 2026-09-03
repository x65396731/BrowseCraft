import Foundation
import GRDB
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：ViewModel 测试的装配根。持久化走临时 SQLite 上的真实 GRDB 仓储与真实用例，
// 只有网络/runtime 边界用 ScriptedSourceRuntime 与 Stub 端口替换，
// 这样 ViewModel 测的是"真实编排 + 真实持久化"，而不是一堆 mock 的互相调用。
enum ViewModelTestHarness {
    static let fixedNow: Date = Date(timeIntervalSince1970: 1_000)

    // MARK: - Database

    static func makeDatabase() throws -> AppDatabase {
        let path: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftViewModelTests-\(UUID().uuidString).sqlite")
            .path
        let database: AppDatabase = try AppDatabase(path: path)
        try database.queue.write { database in
            try AppUserRecord.insertLocalDefaultUser(in: database)
        }
        return database
    }

    /// 中文注释：Reader/History 走真实业务用户 UUID；这里插入 users 行满足外键。
    static func insertUser(_ userID: UUID, into database: AppDatabase) throws {
        try database.queue.write { database in
            try AppUserRecord.insertUser(id: userID.uuidString, in: database)
        }
    }

    // MARK: - Fixtures

    static func makeComicSource(id: String = "comic.test", name: String = "Comic Test") throws -> Source {
        let rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )
        return Source(
            id: id,
            name: name,
            baseURL: rule.baseUrl,
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Self.fixedNow,
            updatedAt: Self.fixedNow
        )
    }

    static func makeRSSSource(id: String = "rss.test", name: String = "RSS Test") -> Source {
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
            createdAt: Self.fixedNow,
            updatedAt: Self.fixedNow
        )
    }

    static func makeItem(
        id: String,
        sourceID: String,
        kind: SourceContentKind = .comic
    ) -> ContentItem {
        return ContentItem(
            id: id,
            sourceId: sourceID,
            title: "Item \(id)",
            detailURL: "https://example.test/item/\(id)",
            coverURL: nil,
            type: kind,
            latestText: nil
        )
    }

    /// 中文注释：按 source id 分发脚本 runtime；未登记的 id 用 fallback（默认空列表）。
    static func resolver(
        _ runtimes: [String: ScriptedSourceRuntime] = [:],
        fallback: ScriptedSourceRuntime? = nil
    ) -> TestSourceRuntimeResolver {
        return TestSourceRuntimeResolver(
            rssRuntimeFactory: { definition in
                return runtimes[definition.id] ?? fallback ?? ScriptedSourceRuntime(definition: definition)
            },
            comicRuntimeFactory: { source in
                return runtimes[source.id] ?? fallback ?? ScriptedSourceRuntime(source: source)
            }
        )
    }

    // MARK: - Waiting

    /// 中文注释：ViewModel 内部用 Task / Combine 异步落库和回传；轮询直到条件成立或超时。
    @MainActor
    static func waitUntil(
        timeoutSeconds: TimeInterval = 3,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    // MARK: - ViewModels

    @MainActor
    static func makeLibraryViewModel(
        database: AppDatabase,
        resolver: any SourceRuntimeResolving,
        selectionStore: SourceSelectionStore = SourceSelectionStore(),
        credentialStore: any SourceCredentialStoring = InMemorySourceCredentialStore()
    ) -> LibraryViewModel {
        let sourceRepository: SourceRepository = GRDBSourceRepository(database: database)
        let favoriteRepository: FavoriteRepository = GRDBFavoriteRepository(database: database)
        let userLibraryStateRepository: UserLibraryStateRepository =
            GRDBUserLibraryStateRepository(database: database)
        return LibraryViewModel(
            persistenceCoordinator: LibraryPersistenceCoordinator(
                syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase(sourceRepository: sourceRepository),
                reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase(
                    sourceRepository: sourceRepository
                ),
                toggleFavoriteUseCase: ToggleFavoriteUseCase(favoriteRepository: favoriteRepository),
                loadUserLibraryStateUseCase: LoadUserLibraryStateUseCase(
                    repository: userLibraryStateRepository
                ),
                saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase(
                    repository: userLibraryStateRepository
                )
            ),
            refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase(runtimeResolver: resolver),
            resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase(),
            sourceCredentialStore: credentialStore,
            sourceSelectionStore: selectionStore,
            now: { Self.fixedNow }
        )
    }

    @MainActor
    static func makeSourcesViewModel(
        database: AppDatabase,
        resolver: any SourceRuntimeResolving,
        selectionStore: SourceSelectionStore = SourceSelectionStore(),
        rssFeedLoader: any RSSFeedLoading = ScriptedRSSFeedLoader()
    ) -> SourcesViewModel {
        let sourceRepository: SourceRepository = GRDBSourceRepository(database: database)
        let userLibraryStateRepository: UserLibraryStateRepository =
            GRDBUserLibraryStateRepository(database: database)
        let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase =
            RefreshSourceRuntimeUseCase(runtimeResolver: resolver)
        let persistenceCoordinator: SourcesPersistenceCoordinator = SourcesPersistenceCoordinator(
            syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase(sourceRepository: sourceRepository),
            loadSourceSlotLimitUseCase: LoadSourceSlotLimitUseCase(
                appUserRepository: GRDBAppUserRepository(database: database)
            ),
            reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase(
                sourceRepository: sourceRepository
            ),
            activateSourceSlotUseCase: ActivateSourceSlotUseCase(sourceRepository: sourceRepository),
            deleteSourceUseCase: DeleteSourceUseCase(sourceRepository: sourceRepository),
            saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase(repository: userLibraryStateRepository),
            saveTemporaryResourceHistoryUseCase: SaveTemporaryResourceHistoryUseCase(
                repository: GRDBTemporaryResourceHistoryRepository(database: database)
            )
        )
        let discoveryService: SourceDiscoveryService = SourceDiscoveryService(
            discoverComicResourcesUseCase: DiscoverComicResourcesUseCase(
                pageContentLoader: StubPageContentLoader(),
                htmlParser: CoreHTMLDiscoveryParser()
            ),
            discoverVideoResourcesUseCase: DiscoverVideoResourcesUseCase(
                pageContentLoader: StubPageContentLoader(),
                htmlParser: CoreHTMLDiscoveryParser()
            ),
            discoverRSSFeedsUseCase: DiscoverRSSFeedsUseCase(
                rssFeedLoader: rssFeedLoader,
                loadRSSHubDiscoveryCandidatesUseCase: LoadRSSHubDiscoveryCandidatesUseCase(
                    pageDataLoader: StubPageDataLoader()
                )
            ),
            assessVideoGenerationInputUseCase: AssessVideoGenerationInputUseCase(
                publicURLPolicy: StubPublicURLPolicy(),
                httpLoader: StubPreflightPageLoader(),
                renderedLoader: StubPreflightRenderedPageLoader(),
                structureObserver: DefaultSourceListStructureObserver(),
                entryFamilyAssessor: DefaultSourceListEntryFamilyAssessor()
            )
        )
        let ruleEditorService: SourceRuleEditorService = SourceRuleEditorService(
            updateSourceRuleUseCase: UpdateSourceRuleUseCase(sourceRepository: sourceRepository),
            updateVideoSourceConfigurationUseCase: UpdateVideoSourceConfigurationUseCase(
                sourceRepository: sourceRepository
            ),
            duplicateSourceRuleUseCase: DuplicateSourceRuleUseCase(sourceRepository: sourceRepository),
            exportSourceRulePackageUseCase: ExportSourceRulePackageUseCase(sourceRepository: sourceRepository),
            importSourceRulePackageUseCase: ImportSourceRulePackageUseCase(sourceRepository: sourceRepository)
        )
        return SourcesViewModel(
            persistenceCoordinator: persistenceCoordinator,
            addComicRuleSourceUseCase: AddComicRuleSourceUseCase(
                sourceRepository: sourceRepository,
                refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase
            ),
            addRSSSourceUseCase: AddRSSSourceUseCase(
                sourceRepository: sourceRepository,
                feedLoader: rssFeedLoader,
                refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase,
                now: { Self.fixedNow }
            ),
            discoveryService: discoveryService,
            createVideoGenerationTaskUseCase: nil,
            catalogService: SourceCatalogService(
                addCatalogSourceUseCase: AddCatalogSourceUseCase(
                    sourceRepository: sourceRepository,
                    refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase
                ),
                loadCatalogSourcesUseCase: LoadCatalogSourcesUseCase(pageDataLoader: StubPageDataLoader())
            ),
            ruleEditorService: ruleEditorService,
            ruleEditingCoordinator: SourceRuleEditingCoordinator(service: ruleEditorService),
            recommendSourceImportOptionUseCase: RecommendSourceImportOptionUseCase(),
            refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase,
            validateSourceTabsUseCase: ValidateSourceTabsUseCase(
                refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase,
                rssFeedLoader: rssFeedLoader
            ),
            sourceSelectionStore: selectionStore,
            now: { Self.fixedNow }
        )
    }

    @MainActor
    static func makeReaderViewModel(
        database: AppDatabase,
        resolver: any SourceRuntimeResolving,
        source: Source,
        item: ContentItem,
        userID: UUID,
        selectedChapter: ChapterLink? = nil,
        restoreContext: ReaderHistoryRestoreContext? = nil,
        credentialStore: (any SourceCredentialStoring)? = nil
    ) -> ReaderViewModel {
        let activeAppUser: ActiveAppUserStore = ActiveAppUserStore(initialUserID: userID)
        return ReaderViewModel(
            item: item,
            source: source,
            selectedChapter: selectedChapter,
            restoreContext: restoreContext,
            loadReaderChapterUseCase: LoadReaderChapterUseCase(runtimeResolver: resolver),
            sourceCredentialStore: credentialStore,
            resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase(),
            persistenceCoordinator: ReadingActivityPersistenceCoordinator(
                rssRepository: GRDBRSSReadingHistoryRepository(database: database),
                comicRepository: GRDBComicChapterHistoryRepository(database: database),
                videoRepository: GRDBVideoWatchHistoryRepository(database: database),
                appUserRepository: GRDBAppUserRepository(database: database),
                activeAppUser: activeAppUser
            ),
            activeAppUser: activeAppUser,
            now: { Self.fixedNow }
        )
    }
}
