import BrowseCraftDomain
import BrowseCraftRuntime

struct LibraryFeatureFactory {
    private let database: AppDatabase
    private let activeAppUser: any ActiveAppUserProviding
    private let sourceRepository: SourceRepository
    private let favoriteRepository: FavoriteRepository
    private let sourceCredentialStore: SourceCredentialStoring
    private let protectedResourceLoader: ReaderProtectedResourceLoader
    private let sourceRuntimeFactory: SourceRuntimeFactory
    private let sourceSelectionStore: SourceSelectionStore
    private let systemCookieHeaderProvider: any SystemCookieHeaderProviding
    private let prepareReaderHistoryRestoreUseCase: PrepareReaderHistoryRestoreUseCase
    private let readingActivityPersistenceCoordinator: ReadingActivityPersistenceCoordinator

    init(
        database: AppDatabase,
        activeAppUser: any ActiveAppUserProviding,
        sourceRepository: SourceRepository,
        favoriteRepository: FavoriteRepository,
        sourceCredentialStore: SourceCredentialStoring,
        protectedResourceLoader: ReaderProtectedResourceLoader,
        sourceRuntimeFactory: SourceRuntimeFactory,
        sourceSelectionStore: SourceSelectionStore,
        systemCookieHeaderProvider: any SystemCookieHeaderProviding,
        prepareReaderHistoryRestoreUseCase: PrepareReaderHistoryRestoreUseCase
    ) {
        self.database = database
        self.activeAppUser = activeAppUser
        self.sourceRepository = sourceRepository
        self.favoriteRepository = favoriteRepository
        self.sourceCredentialStore = sourceCredentialStore
        self.protectedResourceLoader = protectedResourceLoader
        self.sourceRuntimeFactory = sourceRuntimeFactory
        self.sourceSelectionStore = sourceSelectionStore
        self.systemCookieHeaderProvider = systemCookieHeaderProvider
        self.prepareReaderHistoryRestoreUseCase = prepareReaderHistoryRestoreUseCase
        self.readingActivityPersistenceCoordinator = ReadingActivityPersistenceCoordinator(
            rssRepository: GRDBRSSReadingHistoryRepository(database: database),
            comicRepository: GRDBComicChapterHistoryRepository(database: database),
            videoRepository: GRDBVideoWatchHistoryRepository(database: database),
            appUserRepository: GRDBAppUserRepository(database: database),
            activeAppUser: activeAppUser
        )
    }

    @MainActor
    func makeViewModel() -> LibraryViewModel {
        let userLibraryStateRepository: UserLibraryStateRepository = GRDBUserLibraryStateRepository(
            database: self.database
        )
        return LibraryViewModel(
            persistenceCoordinator: LibraryPersistenceCoordinator(
                syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase(
                    sourceRepository: self.sourceRepository
                ),
                reconcileSourceSlotAssignmentsUseCase:
                    ReconcileSourceSlotAssignmentsUseCase(
                        sourceRepository: self.sourceRepository
                    ),
                toggleFavoriteUseCase: ToggleFavoriteUseCase(
                    favoriteRepository: self.favoriteRepository
                ),
                loadUserLibraryStateUseCase: LoadUserLibraryStateUseCase(
                    repository: userLibraryStateRepository
                ),
                saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase(
                    repository: userLibraryStateRepository
                )
            ),
            refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase(
                runtimeResolver: self.sourceRuntimeFactory
            ),
            resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase(),
            sourceCredentialStore: self.sourceCredentialStore,
            sourceSelectionStore: self.sourceSelectionStore,
            activeAppUser: self.activeAppUser,
            searchSourceContentUseCase: SearchSourceContentUseCase(
                runtimeResolver: self.sourceRuntimeFactory
            )
        )
    }

    @MainActor
    func makeComicDetailViewModel(item: ContentItem, source: Source) -> ComicDetailViewModel {
        return ComicDetailViewModel(
            item: item,
            source: source,
            loadComicDetailUseCase: LoadComicDetailUseCase(
                runtimeResolver: self.sourceRuntimeFactory
            ),
            persistenceCoordinator: self.readingActivityPersistenceCoordinator,
            resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase(),
            sourceCredentialStore: self.sourceCredentialStore,
            activeAppUser: self.activeAppUser
        )
    }

    @MainActor
    func makeReaderViewModel(
        item: ContentItem,
        source: Source,
        selectedChapter: ChapterLink? = nil,
        restoreContext: ReaderHistoryRestoreContext? = nil
    ) -> ReaderViewModel {
        return ReaderViewModel(
            item: item,
            source: source,
            selectedChapter: selectedChapter,
            restoreContext: restoreContext,
            loadReaderChapterUseCase: LoadReaderChapterUseCase(
                runtimeResolver: self.sourceRuntimeFactory
            ),
            protectedResourceLoader: self.protectedResourceLoader,
            sourceCredentialProvider: self.sourceCredentialStore,
            sourceCredentialStore: self.sourceCredentialStore,
            resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase(),
            persistenceCoordinator: self.readingActivityPersistenceCoordinator,
            activeAppUser: self.activeAppUser
        )
    }

    @MainActor
    func makeReaderViewModel(history: ComicChapterHistory, source: Source) -> ReaderViewModel {
        let plan: ReaderHistoryRestorePlan = self.prepareReaderHistoryRestoreUseCase.execute(
            history: history
        )
        return self.makeReaderViewModel(
            item: plan.item,
            source: source,
            selectedChapter: plan.selectedChapter,
            restoreContext: ReaderHistoryRestoreContext(
                lastPageIndex: plan.lastPageIndex,
                lastPageImageURLString: plan.lastPageImageURLString
            )
        )
    }

    @MainActor
    func makeRSSContentDetailViewModel(item: ContentItem, source: Source) -> RSSContentDetailViewModel {
        return RSSContentDetailViewModel(
            item: item,
            source: source,
            persistenceCoordinator: self.readingActivityPersistenceCoordinator,
            runtimeResolver: self.sourceRuntimeFactory,
            activeAppUser: self.activeAppUser
        )
    }

    @MainActor
    func makeVideoPlayerViewModel(history: VideoWatchHistory, source: Source) -> VideoPlayerViewModel {
        return VideoPlayerViewModel(
            source: source,
            reference: history.playbackReference(defaultSourceName: source.name),
            videoTitle: history.videoTitle,
            detailURL: history.detailURL,
            coverURL: history.coverURL,
            persistenceCoordinator: self.readingActivityPersistenceCoordinator,
            runtimeResolver: self.sourceRuntimeFactory,
            credentialProvider: self.sourceCredentialStore,
            systemCookieHeaderProvider: self.systemCookieHeaderProvider,
            activeAppUser: self.activeAppUser,
            userID: history.userID
        )
    }

    @MainActor
    func makeVideoDetailViewModel(item: ContentItem, source: Source) -> VideoDetailViewModel {
        return VideoDetailViewModel(
            item: item,
            source: source,
            runtimeResolver: self.sourceRuntimeFactory,
            persistenceCoordinator: self.readingActivityPersistenceCoordinator,
            credentialProvider: self.sourceCredentialStore,
            systemCookieHeaderProvider: self.systemCookieHeaderProvider,
            activeAppUser: self.activeAppUser
        )
    }

}
