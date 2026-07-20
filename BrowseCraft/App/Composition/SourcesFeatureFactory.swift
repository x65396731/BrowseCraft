struct SourcesFeatureFactory {
    private let database: AppDatabase
    private let sourceRepository: SourceRepository
    private let pageContentLoader: PageContentLoader
    private let pageDataLoader: PageDataLoader
    private let urlResolver: URLResolvingService
    private let sourceRuntimeFactory: SourceRuntimeFactory
    private let sourceSelectionStore: SourceSelectionStore

    init(
        database: AppDatabase,
        sourceRepository: SourceRepository,
        pageContentLoader: PageContentLoader,
        pageDataLoader: PageDataLoader,
        urlResolver: URLResolvingService,
        sourceRuntimeFactory: SourceRuntimeFactory,
        sourceSelectionStore: SourceSelectionStore
    ) {
        self.database = database
        self.sourceRepository = sourceRepository
        self.pageContentLoader = pageContentLoader
        self.pageDataLoader = pageDataLoader
        self.urlResolver = urlResolver
        self.sourceRuntimeFactory = sourceRuntimeFactory
        self.sourceSelectionStore = sourceSelectionStore
    }

    func makeViewModel() -> SourcesViewModel {
        let userLibraryStateRepository: UserLibraryStateRepository = GRDBUserLibraryStateRepository(
            database: self.database
        )
        let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase = RefreshSourceRuntimeUseCase(
            runtimeResolver: self.sourceRuntimeFactory
        )
        let loadRSSHubDiscoveryCandidatesUseCase: LoadRSSHubDiscoveryCandidatesUseCase =
            LoadRSSHubDiscoveryCandidatesUseCase(pageDataLoader: self.pageDataLoader)
        let sourceDiscoveryService: SourceDiscoveryService = SourceDiscoveryService(
            discoverComicResourcesUseCase: DiscoverComicResourcesUseCase(
                pageContentLoader: self.pageContentLoader,
                htmlParser: SwiftSoupHTMLDiscoveryParser(),
                urlResolver: self.urlResolver
            ),
            discoverVideoResourcesUseCase: DiscoverVideoResourcesUseCase(
                pageContentLoader: self.pageContentLoader,
                htmlParser: SwiftSoupHTMLDiscoveryParser(),
                urlResolver: self.urlResolver
            ),
            discoverRSSFeedsUseCase: DiscoverRSSFeedsUseCase(
                rssFeedLoader: RSSFeedLoader(pageDataLoader: self.pageDataLoader),
                loadRSSHubDiscoveryCandidatesUseCase: loadRSSHubDiscoveryCandidatesUseCase
            ),
            saveTemporaryResourceHistoryUseCase: SaveTemporaryResourceHistoryUseCase(
                repository: GRDBTemporaryResourceHistoryRepository(database: self.database)
            )
        )
        let sourceRuleEditorService: SourceRuleEditorService = SourceRuleEditorService(
            updateSourceRuleUseCase: UpdateSourceRuleUseCase(
                sourceRepository: self.sourceRepository
            ),
            updateVideoSourceConfigurationUseCase: UpdateVideoSourceConfigurationUseCase(
                sourceRepository: self.sourceRepository
            ),
            duplicateSourceRuleUseCase: DuplicateSourceRuleUseCase(
                sourceRepository: self.sourceRepository
            ),
            exportSourceRulePackageUseCase: ExportSourceRulePackageUseCase(
                sourceRepository: self.sourceRepository
            ),
            importSourceRulePackageUseCase: ImportSourceRulePackageUseCase(
                sourceRepository: self.sourceRepository
            )
        )
        let portalRequestHeaderProvider: PortalRequestHeaderProvider = PortalRequestHeaderProvider(
            appUserRepository: GRDBAppUserRepository(database: self.database)
        )
        let sourceCatalogService: SourceCatalogService = SourceCatalogService(
            addCatalogSourceUseCase: AddCatalogSourceUseCase(
                sourceRepository: self.sourceRepository,
                refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase
            ),
            loadCatalogSourcesUseCase: LoadCatalogSourcesUseCase(
                pageDataLoader: self.pageDataLoader,
                requestHeaders: portalRequestHeaderProvider.headers
            )
        )

        return SourcesViewModel(
            syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase(
                sourceRepository: self.sourceRepository
            ),
            loadSourcesUseCase: LoadSourcesUseCase(
                sourceRepository: self.sourceRepository
            ),
            addComicRuleSourceUseCase: AddComicRuleSourceUseCase(
                sourceRepository: self.sourceRepository,
                refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase
            ),
            addRSSSourceUseCase: AddRSSSourceUseCase(
                sourceRepository: self.sourceRepository,
                feedLoader: RSSFeedLoader(pageDataLoader: self.pageDataLoader),
                refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase
            ),
            discoveryService: sourceDiscoveryService,
            catalogService: sourceCatalogService,
            deleteSourceUseCase: DeleteSourceUseCase(
                sourceRepository: self.sourceRepository
            ),
            ruleEditorService: sourceRuleEditorService,
            recommendSourceImportOptionUseCase: RecommendSourceImportOptionUseCase(),
            refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase,
            validateSourceTabsUseCase: ValidateSourceTabsUseCase(
                refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase,
                rssFeedLoader: RSSFeedLoader(pageDataLoader: self.pageDataLoader)
            ),
            saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase(
                repository: userLibraryStateRepository
            ),
            sourceSelectionStore: self.sourceSelectionStore
        )
    }
}
