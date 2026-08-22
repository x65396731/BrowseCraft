import BrowseCraftCore

struct SourcesFeatureFactory {
    private let database: AppDatabase
    private let activeAppUser: any ActiveAppUserProviding
    private let sourceRepository: SourceRepository
    private let pageContentLoader: PageContentLoader
    private let pageDataLoader: PageDataLoader
    private let urlResolver: URLResolvingService
    private let sourceRuntimeFactory: SourceRuntimeFactory
    private let sourceSelectionStore: SourceSelectionStore

    init(
        database: AppDatabase,
        activeAppUser: any ActiveAppUserProviding,
        sourceRepository: SourceRepository,
        pageContentLoader: PageContentLoader,
        pageDataLoader: PageDataLoader,
        urlResolver: URLResolvingService,
        sourceRuntimeFactory: SourceRuntimeFactory,
        sourceSelectionStore: SourceSelectionStore
    ) {
        self.database = database
        self.activeAppUser = activeAppUser
        self.sourceRepository = sourceRepository
        self.pageContentLoader = pageContentLoader
        self.pageDataLoader = pageDataLoader
        self.urlResolver = urlResolver
        self.sourceRuntimeFactory = sourceRuntimeFactory
        self.sourceSelectionStore = sourceSelectionStore
    }

    @MainActor
    func makeViewModel() -> SourcesViewModel {
        let userLibraryStateRepository: UserLibraryStateRepository = GRDBUserLibraryStateRepository(
            database: self.database
        )
        let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase = RefreshSourceRuntimeUseCase(
            runtimeResolver: self.sourceRuntimeFactory
        )
        let loadRSSHubDiscoveryCandidatesUseCase: LoadRSSHubDiscoveryCandidatesUseCase =
            LoadRSSHubDiscoveryCandidatesUseCase(pageDataLoader: self.pageDataLoader)
        let publicURLPolicy: PublicURLPolicy = PublicURLPolicy()
        let assessVideoGenerationInputUseCase: AssessVideoGenerationInputUseCase =
            AssessVideoGenerationInputUseCase(
                publicURLPolicy: publicURLPolicy,
                httpLoader: PreflightHTTPPageLoader(publicURLPolicy: publicURLPolicy),
                renderedLoader: PreflightRenderedPageLoader(publicURLPolicy: publicURLPolicy),
                structureObserver: DefaultSourceListStructureObserver(),
                familyAssessor: DefaultSourceListFamilyAssessor()
            )
        let sourceDiscoveryService: SourceDiscoveryService = SourceDiscoveryService(
            discoverComicResourcesUseCase: DiscoverComicResourcesUseCase(
                pageContentLoader: self.pageContentLoader,
                htmlParser: CoreHTMLDiscoveryParser(),
                urlResolver: self.urlResolver
            ),
            discoverVideoResourcesUseCase: DiscoverVideoResourcesUseCase(
                pageContentLoader: self.pageContentLoader,
                htmlParser: CoreHTMLDiscoveryParser(),
                urlResolver: self.urlResolver
            ),
            discoverRSSFeedsUseCase: DiscoverRSSFeedsUseCase(
                rssFeedLoader: RSSFeedLoader(pageDataLoader: self.pageDataLoader),
                loadRSSHubDiscoveryCandidatesUseCase: loadRSSHubDiscoveryCandidatesUseCase
            ),
            assessVideoGenerationInputUseCase: assessVideoGenerationInputUseCase
        )
        let sourceRuleEditorService: SourceRuleEditorService = self.makeSourceRuleEditorService()
        let sourceRuleEditingCoordinator: SourceRuleEditingCoordinator =
            SourceRuleEditingCoordinator(service: self.makeSourceRuleEditorService())
        let portalRequestHeaderProvider: PortalRequestHeaderProvider = PortalRequestHeaderProvider(
            activeAppUser: self.activeAppUser
        )
        let sourceCatalogService: SourceCatalogService = SourceCatalogService(
            addCatalogSourceUseCase: AddCatalogSourceUseCase(
                sourceRepository: self.sourceRepository,
                refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase
            ),
            loadCatalogSourcesUseCase: LoadCatalogSourcesUseCase(
                pageDataLoader: self.pageDataLoader,
                requestHeaders: {
                    return portalRequestHeaderProvider.headers()
                }
            )
        )
        let persistenceCoordinator: SourcesPersistenceCoordinator = SourcesPersistenceCoordinator(
            syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase(
                sourceRepository: self.sourceRepository
            ),
            loadSourceSlotLimitUseCase: LoadSourceSlotLimitUseCase(
                appUserRepository: GRDBAppUserRepository(database: self.database)
            ),
            reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase(
                sourceRepository: self.sourceRepository
            ),
            activateSourceSlotUseCase: ActivateSourceSlotUseCase(
                sourceRepository: self.sourceRepository
            ),
            deleteSourceUseCase: DeleteSourceUseCase(
                sourceRepository: self.sourceRepository
            ),
            saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase(
                repository: userLibraryStateRepository
            ),
            saveTemporaryResourceHistoryUseCase: SaveTemporaryResourceHistoryUseCase(
                repository: GRDBTemporaryResourceHistoryRepository(database: self.database)
            )
        )

        return SourcesViewModel(
            persistenceCoordinator: persistenceCoordinator,
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
            ruleEditorService: sourceRuleEditorService,
            ruleEditingCoordinator: sourceRuleEditingCoordinator,
            recommendSourceImportOptionUseCase: RecommendSourceImportOptionUseCase(),
            refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase,
            validateSourceTabsUseCase: ValidateSourceTabsUseCase(
                refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase,
                rssFeedLoader: RSSFeedLoader(pageDataLoader: self.pageDataLoader)
            ),
            sourceSelectionStore: self.sourceSelectionStore,
            activeAppUser: self.activeAppUser
        )
    }

    private func makeSourceRuleEditorService() -> SourceRuleEditorService {
        return SourceRuleEditorService(
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
    }
}
