import Foundation

// 中文注释：AppContainer.swift 属于应用装配和根导航，用于说明本文件承载的核心职责。

/// 中文注释：AppContainer 不是界面，而是应用依赖装配中心。
/// 中文注释：这里统一创建仓储、Alamofire 客户端、SwiftSoup 解析器和各个用例。
final class AppContainer {
    private let database: AppDatabase
    private let sourceRepository: SourceRepository
    private let favoriteRepository: FavoriteRepository
    private let httpClient: HTTPClient
    private let pageContentLoader: PageContentLoader
    private let urlResolver: URLResolvingService
    private let ruleParser: RuleParsingService
    private let sourceRuntimeFactory: SourceRuntimeFactory
    private let sourceSelectionStore: SourceSelectionStore
    /// 中文注释：图片缓存配置器需要和 App 生命周期一致，Settings 变更与启动配置共享同一份 DataCache 实例。
    let imageCacheConfigurator: ImageCacheConfigurator

    init() {
        let imageCacheConfigurator: ImageCacheConfigurator = ImageCacheConfigurator()
        self.imageCacheConfigurator = imageCacheConfigurator

        do {
            let database: AppDatabase = try AppDatabase()
            let urlResolver: URLResolvingService = URLResolvingService()
            let httpClient: HTTPClient = AlamofireHTTPClient()
            let pageContentLoader: PageContentLoader = DefaultPageContentLoader(httpClient: httpClient)
            let ruleParser: RuleParsingService = SwiftSoupRuleParser(urlResolver: urlResolver)

            self.database = database
            self.sourceRepository = GRDBSourceRepository(database: database)
            self.favoriteRepository = GRDBFavoriteRepository(database: database)
            self.httpClient = httpClient
            self.pageContentLoader = pageContentLoader
            self.urlResolver = urlResolver
            self.ruleParser = ruleParser
            self.sourceRuntimeFactory = SourceRuntimeFactory(
                pageContentLoader: pageContentLoader,
                ruleParser: ruleParser,
                urlResolver: urlResolver
            )
            self.sourceSelectionStore = SourceSelectionStore()
        } catch {
            // 中文注释：DB 初始化失败时历史功能无法工作，当前阶段先保持启动期快速暴露错误。
            fatalError("Failed to build AppContainer: \(error)")
        }

        self.configureImageCache()
    }

    private func configureImageCache() {
        do {
            let settings: ImageCacheSettings = try self.imageCacheConfigurator.configureSharedPipeline()
            // 中文注释：启动时主动检查一次旧缓存，避免用户调小上限后旧数据长期留在磁盘。
            self.imageCacheConfigurator.trimConfiguredDataCacheIfNeeded(settings: settings)
            #if DEBUG
            print(
                "[BrowseCraftImageCache] configured " +
                "limit=\(settings.displayTitle) " +
                "limitBytes=\(settings.limitBytes) " +
                "trimTargetBytes=\(settings.trimTargetBytes)"
            )
            #endif
        } catch {
            #if DEBUG
            print("[BrowseCraftImageCache] configuration failed error=\(error)")
            #endif
        }
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        return SettingsViewModel(imageCacheConfigurator: self.imageCacheConfigurator)
    }

    /// 中文注释：makeSourcesViewModel 方法封装当前类型的一段业务或界面行为。
    func makeSourcesViewModel() -> SourcesViewModel {
        let userLibraryStateRepository: UserLibraryStateRepository = GRDBUserLibraryStateRepository(
            database: self.database
        )
        let syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase = SyncBuiltInSourcesUseCase(
            sourceRepository: self.sourceRepository
        )
        let loadSourcesUseCase: LoadSourcesUseCase = LoadSourcesUseCase(
            sourceRepository: self.sourceRepository
        )
        let addComicRuleSourceUseCase: AddComicRuleSourceUseCase = AddComicRuleSourceUseCase(
            sourceRepository: self.sourceRepository
        )
        let addRSSSourceUseCase: AddRSSSourceUseCase = AddRSSSourceUseCase(
            sourceRepository: self.sourceRepository,
            feedLoader: RSSFeedLoader(pageContentLoader: self.pageContentLoader)
        )
        let addVideoSourceUseCase: AddVideoSourceUseCase = AddVideoSourceUseCase(
            sourceRepository: self.sourceRepository
        )
        let deleteSourceUseCase: DeleteSourceUseCase = DeleteSourceUseCase(
            sourceRepository: self.sourceRepository
        )
        let updateSourceRuleUseCase: UpdateSourceRuleUseCase = UpdateSourceRuleUseCase(
            sourceRepository: self.sourceRepository
        )
        let duplicateSourceRuleUseCase: DuplicateSourceRuleUseCase = DuplicateSourceRuleUseCase(
            sourceRepository: self.sourceRepository
        )
        let exportSourceRulePackageUseCase: ExportSourceRulePackageUseCase = ExportSourceRulePackageUseCase(
            sourceRepository: self.sourceRepository
        )
        let importSourceRulePackageUseCase: ImportSourceRulePackageUseCase = ImportSourceRulePackageUseCase(
            sourceRepository: self.sourceRepository
        )
        let recommendSourceImportOptionUseCase: RecommendSourceImportOptionUseCase = RecommendSourceImportOptionUseCase()
        let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase = RefreshSourceRuntimeUseCase(
            runtimeResolver: self.makeSourceRuntimeResolver()
        )
        let addCatalogSourceUseCase: AddCatalogSourceUseCase = AddCatalogSourceUseCase(
            sourceRepository: self.sourceRepository,
            refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase
        )
        let saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase = SaveUserLibraryStateUseCase(
            repository: userLibraryStateRepository
        )
        let ruleCandidateAnalyzer: RuleCandidateAnalyzingService = SwiftSoupRuleSelectorFinder()
        let listDebugUseCase: ListDebugUseCase = ListDebugUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser,
            urlResolver: self.urlResolver,
            candidateAnalyzer: ruleCandidateAnalyzer
        )
        let searchDebugUseCase: SearchDebugUseCase = SearchDebugUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser,
            urlResolver: self.urlResolver,
            candidateAnalyzer: ruleCandidateAnalyzer
        )
        let detailDebugUseCase: DetailDebugUseCase = DetailDebugUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser,
            urlResolver: self.urlResolver,
            candidateAnalyzer: ruleCandidateAnalyzer
        )
        let readerDebugUseCase: ReaderDebugUseCase = ReaderDebugUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser,
            urlResolver: self.urlResolver,
            candidateAnalyzer: ruleCandidateAnalyzer
        )

        return SourcesViewModel(
            syncBuiltInSourcesUseCase: syncBuiltInSourcesUseCase,
            loadSourcesUseCase: loadSourcesUseCase,
            addComicRuleSourceUseCase: addComicRuleSourceUseCase,
            addRSSSourceUseCase: addRSSSourceUseCase,
            addVideoSourceUseCase: addVideoSourceUseCase,
            addCatalogSourceUseCase: addCatalogSourceUseCase,
            deleteSourceUseCase: deleteSourceUseCase,
            updateSourceRuleUseCase: updateSourceRuleUseCase,
            duplicateSourceRuleUseCase: duplicateSourceRuleUseCase,
            exportSourceRulePackageUseCase: exportSourceRulePackageUseCase,
            importSourceRulePackageUseCase: importSourceRulePackageUseCase,
            recommendSourceImportOptionUseCase: recommendSourceImportOptionUseCase,
            refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase,
            saveUserLibraryStateUseCase: saveUserLibraryStateUseCase,
            listDebugUseCase: listDebugUseCase,
            searchDebugUseCase: searchDebugUseCase,
            detailDebugUseCase: detailDebugUseCase,
            readerDebugUseCase: readerDebugUseCase,
            sourceSelectionStore: self.sourceSelectionStore
        )
    }

    /// 中文注释：makeLibraryViewModel 方法封装当前类型的一段业务或界面行为。
    func makeLibraryViewModel() -> LibraryViewModel {
        let userLibraryStateRepository: UserLibraryStateRepository = GRDBUserLibraryStateRepository(
            database: self.database
        )
        let syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase = SyncBuiltInSourcesUseCase(
            sourceRepository: self.sourceRepository
        )
        let loadSourcesUseCase: LoadSourcesUseCase = LoadSourcesUseCase(
            sourceRepository: self.sourceRepository
        )
        let toggleFavoriteUseCase: ToggleFavoriteUseCase = ToggleFavoriteUseCase(
            favoriteRepository: self.favoriteRepository
        )
        let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase = RefreshSourceRuntimeUseCase(
            runtimeResolver: self.makeSourceRuntimeResolver()
        )
        let loadUserLibraryStateUseCase: LoadUserLibraryStateUseCase = LoadUserLibraryStateUseCase(
            repository: userLibraryStateRepository
        )
        let saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase = SaveUserLibraryStateUseCase(
            repository: userLibraryStateRepository
        )

        return LibraryViewModel(
            syncBuiltInSourcesUseCase: syncBuiltInSourcesUseCase,
            loadSourcesUseCase: loadSourcesUseCase,
            toggleFavoriteUseCase: toggleFavoriteUseCase,
            refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase,
            loadUserLibraryStateUseCase: loadUserLibraryStateUseCase,
            saveUserLibraryStateUseCase: saveUserLibraryStateUseCase,
            resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase(),
            sourceSelectionStore: self.sourceSelectionStore
        )
    }

    /// 中文注释：makeChapterListViewModel 方法封装当前类型的一段业务或界面行为。
    func makeChapterListViewModel(item: ContentItem, source: Source) -> ChapterListViewModel {
        let loadChaptersUseCase: LoadChaptersUseCase = LoadChaptersUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser
        )

        return ChapterListViewModel(
            item: item,
            source: source,
            loadChaptersUseCase: loadChaptersUseCase,
            resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase()
        )
    }

    /// 中文注释：makeReaderViewModel 方法封装当前类型的一段业务或界面行为。
    func makeReaderViewModel(
        item: ContentItem,
        source: Source,
        selectedChapter: ChapterLink? = nil,
        restoreContext: ReaderHistoryRestoreContext? = nil
    ) -> ReaderViewModel {
        let loadReaderChapterUseCase: LoadReaderChapterUseCase = LoadReaderChapterUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser
        )
        let repository: ComicChapterHistoryRepository = GRDBComicChapterHistoryRepository(
            database: self.database
        )
        let saveComicChapterHistoryUseCase: SaveComicChapterHistoryUseCase = SaveComicChapterHistoryUseCase(
            repository: repository
        )

        return ReaderViewModel(
            item: item,
            source: source,
            selectedChapter: selectedChapter,
            restoreContext: restoreContext,
            loadReaderChapterUseCase: loadReaderChapterUseCase,
            resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase(),
            saveComicChapterHistoryUseCase: saveComicChapterHistoryUseCase
        )
    }

    func makeReaderViewModel(history: ComicChapterHistory, source: Source) -> ReaderViewModel {
        let readerURL: URL? = history.lastReaderPageURL ?? history.chapterURL
        let item: ContentItem = ContentItem(
            id: history.comicItemID,
            sourceId: history.sourceID,
            title: history.comicTitle,
            detailURL: readerURL?.absoluteString ?? history.comicItemID,
            coverURL: history.coverURL?.absoluteString,
            type: .comic,
            latestText: history.chapterTitle,
            updatedAt: history.visitedAt
        )
        let selectedChapter: ChapterLink? = readerURL.map { url in
            return ChapterLink(title: history.chapterTitle, url: url.absoluteString)
        }
        let restoreContext: ReaderHistoryRestoreContext = ReaderHistoryRestoreContext(
            lastPageIndex: history.lastPageIndex,
            lastPageImageURLString: history.lastPageImageURL?.absoluteString
        )

        return self.makeReaderViewModel(
            item: item,
            source: source,
            selectedChapter: selectedChapter,
            restoreContext: restoreContext
        )
    }

    @MainActor
    func makeRSSContentDetailViewModel(item: ContentItem, source: Source) -> RSSContentDetailViewModel {
        let repository: RSSReadingHistoryRepository = GRDBRSSReadingHistoryRepository(
            database: self.database
        )
        let saveRSSReadingHistoryUseCase: SaveRSSReadingHistoryUseCase = SaveRSSReadingHistoryUseCase(
            repository: repository
        )

        return RSSContentDetailViewModel(
            item: item,
            source: source,
            saveRSSReadingHistoryUseCase: saveRSSReadingHistoryUseCase
        )
    }

    @MainActor
    func makeVideoPlayerViewModel(history: VideoWatchHistory, source: Source) -> VideoPlayerViewModel {
        let repository: VideoWatchHistoryRepository = GRDBVideoWatchHistoryRepository(
            database: self.database
        )
        let saveVideoWatchHistoryUseCase: SaveVideoWatchHistoryUseCase = SaveVideoWatchHistoryUseCase(
            repository: repository
        )
        let loadVideoWatchHistoryUseCase: LoadVideoWatchHistoryUseCase = LoadVideoWatchHistoryUseCase(
            repository: repository
        )
        let reference: SourceVideoPlaybackReference = history.playbackReference(
            defaultSourceName: source.name
        )

        return VideoPlayerViewModel(
            source: source,
            reference: reference,
            videoTitle: history.videoTitle,
            detailURL: history.detailURL,
            coverURL: history.coverURL,
            saveVideoWatchHistoryUseCase: saveVideoWatchHistoryUseCase,
            loadVideoWatchHistoryUseCase: loadVideoWatchHistoryUseCase,
            runtimeResolver: self.makeSourceRuntimeResolver(),
            userID: history.userID
        )
    }

    @MainActor
    func makeVideoDetailViewModel(item: ContentItem, source: Source) -> VideoDetailViewModel {
        let repository: VideoWatchHistoryRepository = GRDBVideoWatchHistoryRepository(
            database: self.database
        )
        let saveVideoWatchHistoryUseCase: SaveVideoWatchHistoryUseCase = SaveVideoWatchHistoryUseCase(
            repository: repository
        )
        let loadVideoWatchHistoryUseCase: LoadVideoWatchHistoryUseCase = LoadVideoWatchHistoryUseCase(
            repository: repository
        )

        return VideoDetailViewModel(
            item: item,
            source: source,
            runtimeResolver: self.makeSourceRuntimeResolver(),
            saveVideoWatchHistoryUseCase: saveVideoWatchHistoryUseCase,
            loadVideoWatchHistoryUseCase: loadVideoWatchHistoryUseCase
        )
    }

    /// 中文注释：漫画 source 当前复用 RuleSourceRuntime 实现；对外入口保持 comic runtime 语义。
    func makeComicSourceRuntime(source: Source) -> RuleSourceRuntime {
        return self.sourceRuntimeFactory.makeComicSourceRuntime(source: source)
    }

    func makeSourceRuntimeResolver() -> any SourceRuntimeResolving {
        return self.sourceRuntimeFactory.makeRuntimeResolver()
    }

    /// 中文注释：makeHistoryViewModel 方法封装当前类型的一段业务或界面行为。
    func makeHistoryViewModel() -> HistoryViewModel {
        let rssRepository: RSSReadingHistoryRepository = GRDBRSSReadingHistoryRepository(
            database: self.database
        )
        let comicRepository: ComicChapterHistoryRepository = GRDBComicChapterHistoryRepository(
            database: self.database
        )
        let videoRepository: VideoWatchHistoryRepository = GRDBVideoWatchHistoryRepository(
            database: self.database
        )
        let loadReadingHistoryEntriesUseCase: LoadReadingHistoryEntriesUseCase = LoadReadingHistoryEntriesUseCase(
            rssRepository: rssRepository,
            comicRepository: comicRepository,
            videoRepository: videoRepository
        )
        let loadSourcesUseCase: LoadSourcesUseCase = LoadSourcesUseCase(
            sourceRepository: self.sourceRepository
        )

        return HistoryViewModel(
            loadReadingHistoryEntriesUseCase: loadReadingHistoryEntriesUseCase,
            loadSourcesUseCase: loadSourcesUseCase,
            videoPlayerViewModelFactory: { history, source in
                return self.makeVideoPlayerViewModel(history: history, source: source)
            }
        )
    }
}
