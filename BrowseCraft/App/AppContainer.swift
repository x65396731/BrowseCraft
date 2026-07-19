import Foundation
import UIKit

// 中文注释：AppContainer.swift 属于应用装配和根导航，用于说明本文件承载的核心职责。

/// 中文注释：AppContainer 不是界面，而是应用依赖装配中心。
/// 中文注释：这里统一创建仓储、Alamofire 客户端、漫画/视频规则解析器和各个用例。
final class AppContainer {
    private let database: AppDatabase
    private let sourceRepository: SourceRepository
    private let favoriteRepository: FavoriteRepository
    private let httpClient: HTTPClient
    private let sourceCredentialStore: SourceCredentialStoring
    private let pageContentLoader: PageContentLoader
    private let pageDataLoader: PageDataLoader
    private let protectedResourceLoader: ReaderProtectedResourceLoader
    private let urlResolver: URLResolvingService
    private let comicRuleParser: ComicRuleSourceParsingService
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
            let sourceCredentialStore: SourceCredentialStoring = InMemorySourceCredentialStore()
            let httpClient: HTTPClient = AlamofireHTTPClient(credentialProvider: sourceCredentialStore)
            let pageContentLoader: DefaultPageContentLoader = DefaultPageContentLoader(
                httpClient: httpClient,
                credentialProvider: sourceCredentialStore
            )
            let comicRuleParser: ComicRuleSourceParsingService = SwiftSoupComicRuleSourceParser(urlResolver: urlResolver)
            let videoRuleParser: VideoRuleSourceParsingService = SwiftSoupVideoRuleSourceParser()

            self.database = database
            self.sourceRepository = GRDBSourceRepository(database: database)
            self.favoriteRepository = GRDBFavoriteRepository(database: database)
            self.httpClient = httpClient
            self.sourceCredentialStore = sourceCredentialStore
            self.pageContentLoader = pageContentLoader
            self.pageDataLoader = pageContentLoader
            self.protectedResourceLoader = ReaderProtectedResourceLoader(
                legacyLoader: ProtectedResourceLoader(dataLoader: pageContentLoader),
                pipelineExecutor: ResourcePipelineExecutor(
                    dataLoader: pageContentLoader,
                    cryptography: CommonCryptoResourcePipelineCryptography()
                )
            )
            self.urlResolver = urlResolver
            self.comicRuleParser = comicRuleParser
            self.sourceRuntimeFactory = SourceRuntimeFactory(
                pageContentLoader: pageContentLoader,
                comicRuleSourceRuntimeFactory: ComicRuleSourceRuntimeFactory(
                    pageContentLoader: pageContentLoader,
                    comicRuleParser: comicRuleParser,
                    urlResolver: urlResolver
                ),
                videoRuleSourceRuntimeFactory: VideoRuleSourceRuntimeFactory(
                    pageContentLoader: pageContentLoader,
                    parser: videoRuleParser,
                    credentialProvider: sourceCredentialStore
                )
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
        return SettingsViewModel(
            imageCacheConfigurator: self.imageCacheConfigurator,
            appUserRepository: GRDBAppUserRepository(database: self.database)
        )
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
        let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase = RefreshSourceRuntimeUseCase(
            runtimeResolver: self.makeSourceRuntimeResolver()
        )
        let addComicRuleSourceUseCase: AddComicRuleSourceUseCase = AddComicRuleSourceUseCase(
            sourceRepository: self.sourceRepository,
            refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase
        )
        let addRSSSourceUseCase: AddRSSSourceUseCase = AddRSSSourceUseCase(
            sourceRepository: self.sourceRepository,
            feedLoader: RSSFeedLoader(pageContentLoader: self.pageContentLoader),
            refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase
        )
        let loadRSSHubDiscoveryCandidatesUseCase: LoadRSSHubDiscoveryCandidatesUseCase =
            LoadRSSHubDiscoveryCandidatesUseCase(
                pageDataLoader: self.pageDataLoader
            )
        let discoverRSSFeedsUseCase: DiscoverRSSFeedsUseCase = DiscoverRSSFeedsUseCase(
            rssFeedLoader: RSSFeedLoader(pageContentLoader: self.pageContentLoader),
            loadRSSHubDiscoveryCandidatesUseCase: loadRSSHubDiscoveryCandidatesUseCase
        )
        let addVideoSourceUseCase: AddVideoSourceUseCase = AddVideoSourceUseCase(
            sourceRepository: self.sourceRepository,
            refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase
        )
        let discoverComicResourcesUseCase: DiscoverComicResourcesUseCase = DiscoverComicResourcesUseCase(
            pageContentLoader: self.pageContentLoader,
            urlResolver: self.urlResolver
        )
        let discoverVideoResourcesUseCase: DiscoverVideoResourcesUseCase = DiscoverVideoResourcesUseCase(
            pageContentLoader: self.pageContentLoader,
            urlResolver: self.urlResolver
        )
        let saveTemporaryResourceHistoryUseCase: SaveTemporaryResourceHistoryUseCase = SaveTemporaryResourceHistoryUseCase(
            repository: GRDBTemporaryResourceHistoryRepository(database: self.database)
        )
        let deleteSourceUseCase: DeleteSourceUseCase = DeleteSourceUseCase(
            sourceRepository: self.sourceRepository
        )
        let updateSourceRuleUseCase: UpdateSourceRuleUseCase = UpdateSourceRuleUseCase(
            sourceRepository: self.sourceRepository
        )
        let updateVideoSourceConfigurationUseCase: UpdateVideoSourceConfigurationUseCase = UpdateVideoSourceConfigurationUseCase(
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
        let addCatalogSourceUseCase: AddCatalogSourceUseCase = AddCatalogSourceUseCase(
            sourceRepository: self.sourceRepository,
            refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase,
            videoTabDiscoveryUseCase: VideoSourceTabDiscoveryUseCase(
                pageContentLoader: self.pageContentLoader
            )
        )
        let portalRequestHeaderProvider: PortalRequestHeaderProvider = PortalRequestHeaderProvider(
            appUserRepository: GRDBAppUserRepository(database: self.database)
        )
        let loadCatalogSourcesUseCase: LoadCatalogSourcesUseCase = LoadCatalogSourcesUseCase(
            pageDataLoader: self.pageDataLoader,
            requestHeaders: portalRequestHeaderProvider.headers
        )
        let saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase = SaveUserLibraryStateUseCase(
            repository: userLibraryStateRepository
        )
        return SourcesViewModel(
            syncBuiltInSourcesUseCase: syncBuiltInSourcesUseCase,
            loadSourcesUseCase: loadSourcesUseCase,
            addComicRuleSourceUseCase: addComicRuleSourceUseCase,
            addRSSSourceUseCase: addRSSSourceUseCase,
            addVideoSourceUseCase: addVideoSourceUseCase,
            discoverComicResourcesUseCase: discoverComicResourcesUseCase,
            discoverVideoResourcesUseCase: discoverVideoResourcesUseCase,
            discoverRSSFeedsUseCase: discoverRSSFeedsUseCase,
            saveTemporaryResourceHistoryUseCase: saveTemporaryResourceHistoryUseCase,
            addCatalogSourceUseCase: addCatalogSourceUseCase,
            loadCatalogSourcesUseCase: loadCatalogSourcesUseCase,
            deleteSourceUseCase: deleteSourceUseCase,
            updateSourceRuleUseCase: updateSourceRuleUseCase,
            updateVideoSourceConfigurationUseCase: updateVideoSourceConfigurationUseCase,
            duplicateSourceRuleUseCase: duplicateSourceRuleUseCase,
            exportSourceRulePackageUseCase: exportSourceRulePackageUseCase,
            importSourceRulePackageUseCase: importSourceRulePackageUseCase,
            recommendSourceImportOptionUseCase: recommendSourceImportOptionUseCase,
            refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase,
            saveUserLibraryStateUseCase: saveUserLibraryStateUseCase,
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
        let videoTabDiscoveryUseCase: VideoSourceTabDiscoveryUseCase = VideoSourceTabDiscoveryUseCase(
            pageContentLoader: self.pageContentLoader
        )
        let validateSourceTabsUseCase: ValidateSourceTabsUseCase = ValidateSourceTabsUseCase(
            refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase,
            rssFeedLoader: RSSFeedLoader(pageContentLoader: self.pageContentLoader),
            videoTabDiscoveryUseCase: videoTabDiscoveryUseCase
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
            videoTabDiscoveryUseCase: videoTabDiscoveryUseCase,
            validateSourceTabsUseCase: validateSourceTabsUseCase,
            loadUserLibraryStateUseCase: loadUserLibraryStateUseCase,
            saveUserLibraryStateUseCase: saveUserLibraryStateUseCase,
            resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase(),
            sourceCredentialStore: self.sourceCredentialStore,
            sourceSelectionStore: self.sourceSelectionStore
        )
    }

    func makeFavoriteViewModel() -> FavoriteViewModel {
        let loadSourcesUseCase: LoadSourcesUseCase = LoadSourcesUseCase(
            sourceRepository: self.sourceRepository
        )
        let loadFavoriteItemsUseCase: ToggleFavoriteUseCase = ToggleFavoriteUseCase(
            favoriteRepository: self.favoriteRepository
        )

        return FavoriteViewModel(
            loadFavoriteItemsUseCase: loadFavoriteItemsUseCase,
            loadSourcesUseCase: loadSourcesUseCase
        )
    }

    /// 中文注释：创建独立漫画详情状态；详情加载不再由 ReaderViewModel 承担。
    @MainActor
    func makeComicDetailViewModel(item: ContentItem, source: Source) -> ComicDetailViewModel {
        let loadComicDetailUseCase: LoadComicDetailUseCase = LoadComicDetailUseCase(
            runtimeResolver: self.sourceRuntimeFactory.makeRuntimeResolver()
        )
        let comicChapterHistoryRepository: ComicChapterHistoryRepository = GRDBComicChapterHistoryRepository(
            database: self.database
        )
        let loadLatestComicChapterHistoryUseCase: LoadLatestComicChapterHistoryUseCase =
            LoadLatestComicChapterHistoryUseCase(repository: comicChapterHistoryRepository)

        return ComicDetailViewModel(
            item: item,
            source: source,
            loadComicDetailUseCase: loadComicDetailUseCase,
            loadLatestComicChapterHistoryUseCase: loadLatestComicChapterHistoryUseCase,
            resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase(),
            sourceCredentialStore: self.sourceCredentialStore
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
            runtimeResolver: self.sourceRuntimeFactory.makeRuntimeResolver()
        )
        let repository: ComicChapterHistoryRepository = GRDBComicChapterHistoryRepository(
            database: self.database
        )
        let saveComicChapterHistoryUseCase: SaveComicChapterHistoryUseCase = SaveComicChapterHistoryUseCase(
            repository: repository
        )
        let accumulateAdPointsUseCase: AccumulateAdPointsUseCase = self.makeAccumulateAdPointsUseCase()

        return ReaderViewModel(
            item: item,
            source: source,
            selectedChapter: selectedChapter,
            restoreContext: restoreContext,
            loadReaderChapterUseCase: loadReaderChapterUseCase,
            protectedResourceLoader: self.protectedResourceLoader,
            sourceCredentialProvider: self.sourceCredentialStore,
            sourceCredentialStore: self.sourceCredentialStore,
            resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase(),
            saveComicChapterHistoryUseCase: saveComicChapterHistoryUseCase,
            accumulateAdPointsUseCase: accumulateAdPointsUseCase
        )
    }

    func makeReaderViewModel(history: ComicChapterHistory, source: Source) -> ReaderViewModel {
        let repository: ComicChapterHistoryRepository = GRDBComicChapterHistoryRepository(
            database: self.database
        )
        let storedChapterTitlesByURL: [String: String] = (try? repository.fetchHistory(userID: history.userID))?
            .filter { storedHistory in
                return storedHistory.sourceID == history.sourceID
                    && storedHistory.comicItemID == history.comicItemID
            }
            .reduce(into: [:]) { titles, storedHistory in
                guard let chapterURL: String = storedHistory.chapterURL?.absoluteString else {
                    return
                }
                titles[chapterURL] = storedHistory.chapterTitle
            } ?? [:]
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
            var navigationChapterURLs: [String] = []
            var navigationChapterTitles: [String?] = []
            let appendNavigationChapter: (URL?, String?) -> Void = { chapterURL, storedTitle in
                guard let chapterURL: URL else {
                    return
                }
                navigationChapterURLs.append(chapterURL.absoluteString)
                navigationChapterTitles.append(
                    storedTitle ?? storedChapterTitlesByURL[chapterURL.absoluteString]
                )
            }
            appendNavigationChapter(history.nextChapterURL, history.nextChapterTitle)
            appendNavigationChapter(url, history.chapterTitle)
            appendNavigationChapter(history.previousChapterURL, history.previousChapterTitle)
            return ChapterLink(
                title: history.chapterTitle,
                url: url.absoluteString,
                navigationChapterURLs: navigationChapterURLs,
                navigationChapterTitles: navigationChapterTitles
            )
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
        let accumulateAdPointsUseCase: AccumulateAdPointsUseCase = self.makeAccumulateAdPointsUseCase()

        return RSSContentDetailViewModel(
            item: item,
            source: source,
            saveRSSReadingHistoryUseCase: saveRSSReadingHistoryUseCase,
            accumulateAdPointsUseCase: accumulateAdPointsUseCase,
            runtimeResolver: self.sourceRuntimeFactory.makeRuntimeResolver()
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
            accumulateAdPointsUseCase: self.makeAccumulateAdPointsUseCase(),
            runtimeResolver: self.makeSourceRuntimeResolver(),
            credentialProvider: self.sourceCredentialStore,
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
            loadVideoWatchHistoryUseCase: loadVideoWatchHistoryUseCase,
            accumulateAdPointsUseCase: self.makeAccumulateAdPointsUseCase(),
            credentialProvider: self.sourceCredentialStore
        )
    }

    /// 中文注释：漫画 source 通过 ComicRuleSourceRuntime 执行；对外入口保持 comic runtime 语义。
    func makeComicSourceRuntime(source: Source) -> ComicRuleSourceRuntime {
        return self.sourceRuntimeFactory.makeComicSourceRuntime(source: source)
    }

    func makeSourceRuntimeResolver() -> any SourceRuntimeResolving {
        return self.sourceRuntimeFactory.makeRuntimeResolver()
    }

    private func makeAccumulateAdPointsUseCase() -> AccumulateAdPointsUseCase {
        return AccumulateAdPointsUseCase(
            repository: GRDBAppUserRepository(database: self.database)
        )
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
        let temporaryRepository: TemporaryResourceHistoryRepository = GRDBTemporaryResourceHistoryRepository(
            database: self.database
        )
        let loadReadingHistoryEntriesUseCase: LoadReadingHistoryEntriesUseCase = LoadReadingHistoryEntriesUseCase(
            rssRepository: rssRepository,
            comicRepository: comicRepository,
            videoRepository: videoRepository,
            temporaryRepository: temporaryRepository
        )
        let deleteReadingHistoryEntryUseCase: DeleteReadingHistoryEntryUseCase = DeleteReadingHistoryEntryUseCase(
            rssRepository: rssRepository,
            comicRepository: comicRepository,
            videoRepository: videoRepository,
            temporaryRepository: temporaryRepository
        )
        let loadSourcesUseCase: LoadSourcesUseCase = LoadSourcesUseCase(
            sourceRepository: self.sourceRepository
        )

        return HistoryViewModel(
            loadReadingHistoryEntriesUseCase: loadReadingHistoryEntriesUseCase,
            deleteReadingHistoryEntryUseCase: deleteReadingHistoryEntryUseCase,
            loadSourcesUseCase: loadSourcesUseCase,
            videoPlayerViewModelFactory: { history, source in
                return self.makeVideoPlayerViewModel(history: history, source: source)
            }
        )
    }
}

// 中文注释：PortalRequestHeaderProvider 只给自家 Portal API 生成业务请求头，避免泄漏到第三方站点。
private struct PortalRequestHeaderProvider {
    private let appUserRepository: AppUserRepository

    init(appUserRepository: AppUserRepository) {
        self.appUserRepository = appUserRepository
    }

    func headers() -> [String: String] {
        return APIRequestHeaders.portalHeaders(
            userID: self.userID(),
            osInfo: self.osInfo,
            deviceInfo: self.deviceInfo,
            appVersion: self.appVersion
        )
    }

    private func userID() -> String {
        do {
            return try self.appUserRepository.fetchUser(id: AppUser.localDefaultID)?.id ?? AppUser.localDefaultID
        } catch {
            return AppUser.localDefaultID
        }
    }

    private var osInfo: String {
        let device: UIDevice = UIDevice.current
        return "\(device.systemName) \(device.systemVersion)"
    }

    private var deviceInfo: String {
        return Self.hardwareIdentifier() ?? UIDevice.current.model
    }

    private var appVersion: String {
        let info: [String: Any] = Bundle.main.infoDictionary ?? [:]
        let version: String = info["CFBundleShortVersionString"] as? String ?? "0"
        let build: String = info["CFBundleVersion"] as? String ?? "0"
        return "\(version)(\(build))"
    }

    private static func hardwareIdentifier() -> String? {
        var systemInfo = utsname()
        uname(&systemInfo)

        let mirror: Mirror = Mirror(reflecting: systemInfo.machine)
        let identifier: String = mirror.children.reduce(into: "") { result, element in
            guard let value: Int8 = element.value as? Int8, value != 0 else {
                return
            }
            result.append(String(UnicodeScalar(UInt8(value))))
        }

        return identifier.isEmpty ? nil : identifier
    }
}
