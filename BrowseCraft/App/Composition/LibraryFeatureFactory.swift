struct LibraryFeatureFactory {
    private let database: AppDatabase
    private let sourceRepository: SourceRepository
    private let favoriteRepository: FavoriteRepository
    private let sourceCredentialStore: SourceCredentialStoring
    private let protectedResourceLoader: ReaderProtectedResourceLoader
    private let sourceRuntimeFactory: SourceRuntimeFactory
    private let sourceSelectionStore: SourceSelectionStore
    private let systemCookieHeaderProvider: any SystemCookieHeaderProviding
    private let prepareReaderHistoryRestoreUseCase: PrepareReaderHistoryRestoreUseCase

    init(
        database: AppDatabase,
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
        self.sourceRepository = sourceRepository
        self.favoriteRepository = favoriteRepository
        self.sourceCredentialStore = sourceCredentialStore
        self.protectedResourceLoader = protectedResourceLoader
        self.sourceRuntimeFactory = sourceRuntimeFactory
        self.sourceSelectionStore = sourceSelectionStore
        self.systemCookieHeaderProvider = systemCookieHeaderProvider
        self.prepareReaderHistoryRestoreUseCase = prepareReaderHistoryRestoreUseCase
    }

    func makeViewModel() -> LibraryViewModel {
        let userLibraryStateRepository: UserLibraryStateRepository = GRDBUserLibraryStateRepository(
            database: self.database
        )
        return LibraryViewModel(
            syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase(
                sourceRepository: self.sourceRepository
            ),
            loadSourcesUseCase: LoadSourcesUseCase(
                sourceRepository: self.sourceRepository
            ),
            toggleFavoriteUseCase: ToggleFavoriteUseCase(
                favoriteRepository: self.favoriteRepository
            ),
            refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase(
                runtimeResolver: self.sourceRuntimeFactory
            ),
            loadUserLibraryStateUseCase: LoadUserLibraryStateUseCase(
                repository: userLibraryStateRepository
            ),
            saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase(
                repository: userLibraryStateRepository
            ),
            resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase(),
            sourceCredentialStore: self.sourceCredentialStore,
            sourceSelectionStore: self.sourceSelectionStore
        )
    }

    @MainActor
    func makeComicDetailViewModel(item: ContentItem, source: Source) -> ComicDetailViewModel {
        let comicChapterHistoryRepository: ComicChapterHistoryRepository = GRDBComicChapterHistoryRepository(
            database: self.database
        )
        return ComicDetailViewModel(
            item: item,
            source: source,
            loadComicDetailUseCase: LoadComicDetailUseCase(
                runtimeResolver: self.sourceRuntimeFactory
            ),
            loadLatestComicChapterHistoryUseCase: LoadLatestComicChapterHistoryUseCase(
                repository: comicChapterHistoryRepository
            ),
            resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase(),
            sourceCredentialStore: self.sourceCredentialStore
        )
    }

    func makeReaderViewModel(
        item: ContentItem,
        source: Source,
        selectedChapter: ChapterLink? = nil,
        restoreContext: ReaderHistoryRestoreContext? = nil
    ) -> ReaderViewModel {
        let repository: ComicChapterHistoryRepository = GRDBComicChapterHistoryRepository(
            database: self.database
        )
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
            saveComicChapterHistoryUseCase: SaveComicChapterHistoryUseCase(
                repository: repository
            ),
            accumulateAdPointsUseCase: self.makeAccumulateAdPointsUseCase()
        )
    }

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
        let repository: RSSReadingHistoryRepository = GRDBRSSReadingHistoryRepository(
            database: self.database
        )
        return RSSContentDetailViewModel(
            item: item,
            source: source,
            saveRSSReadingHistoryUseCase: SaveRSSReadingHistoryUseCase(
                repository: repository
            ),
            accumulateAdPointsUseCase: self.makeAccumulateAdPointsUseCase(),
            runtimeResolver: self.sourceRuntimeFactory
        )
    }

    @MainActor
    func makeVideoPlayerViewModel(history: VideoWatchHistory, source: Source) -> VideoPlayerViewModel {
        let repository: VideoWatchHistoryRepository = GRDBVideoWatchHistoryRepository(
            database: self.database
        )
        return VideoPlayerViewModel(
            source: source,
            reference: history.playbackReference(defaultSourceName: source.name),
            videoTitle: history.videoTitle,
            detailURL: history.detailURL,
            coverURL: history.coverURL,
            saveVideoWatchHistoryUseCase: SaveVideoWatchHistoryUseCase(repository: repository),
            loadVideoWatchHistoryUseCase: LoadVideoWatchHistoryUseCase(repository: repository),
            accumulateAdPointsUseCase: self.makeAccumulateAdPointsUseCase(),
            runtimeResolver: self.sourceRuntimeFactory,
            credentialProvider: self.sourceCredentialStore,
            systemCookieHeaderProvider: self.systemCookieHeaderProvider,
            userID: history.userID
        )
    }

    @MainActor
    func makeVideoDetailViewModel(item: ContentItem, source: Source) -> VideoDetailViewModel {
        let repository: VideoWatchHistoryRepository = GRDBVideoWatchHistoryRepository(
            database: self.database
        )
        return VideoDetailViewModel(
            item: item,
            source: source,
            runtimeResolver: self.sourceRuntimeFactory,
            saveVideoWatchHistoryUseCase: SaveVideoWatchHistoryUseCase(repository: repository),
            loadVideoWatchHistoryUseCase: LoadVideoWatchHistoryUseCase(repository: repository),
            accumulateAdPointsUseCase: self.makeAccumulateAdPointsUseCase(),
            credentialProvider: self.sourceCredentialStore,
            systemCookieHeaderProvider: self.systemCookieHeaderProvider
        )
    }

    private func makeAccumulateAdPointsUseCase() -> AccumulateAdPointsUseCase {
        return AccumulateAdPointsUseCase(
            repository: GRDBAppUserRepository(database: self.database)
        )
    }
}
