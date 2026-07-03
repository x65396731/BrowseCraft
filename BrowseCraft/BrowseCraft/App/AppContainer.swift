import Foundation

// 中文注释：AppContainer.swift 属于应用装配和根导航，用于说明本文件承载的核心职责。

/// 中文注释：AppContainer 不是界面，而是应用依赖装配中心。
/// 中文注释：这里统一创建 GRDB 仓储、Alamofire 客户端、SwiftSoup 解析器和各个用例。
final class AppContainer {
    private let database: AppDatabase
    private let sourceRepository: SourceRepository
    private let contentRepository: ContentRepository
    private let favoriteRepository: FavoriteRepository
    private let historyRepository: HistoryRepository
    private let httpClient: HTTPClient
    private let pageContentLoader: PageContentLoader
    private let urlResolver: URLResolvingService
    private let ruleParser: RuleParsingService
    private let sourceSelectionStore: SourceSelectionStore

    init() {
        do {
            let database: AppDatabase = try AppDatabase()
            let urlResolver: URLResolvingService = URLResolvingService()
            let httpClient: HTTPClient = AlamofireHTTPClient()

            self.database = database
            self.sourceRepository = GRDBSourceRepository(database: database)
            self.contentRepository = GRDBContentRepository(database: database)
            self.favoriteRepository = GRDBFavoriteRepository(database: database)
            self.historyRepository = GRDBHistoryRepository(database: database)
            self.httpClient = httpClient
            self.pageContentLoader = DefaultPageContentLoader(httpClient: httpClient)
            self.urlResolver = urlResolver
            self.ruleParser = SwiftSoupRuleParser(urlResolver: urlResolver)
            self.sourceSelectionStore = SourceSelectionStore()
        } catch {
            // 中文注释：数据库启动失败时应用无法继续运行，后续可以替换为用户可见的恢复页面。
            fatalError("Failed to build AppContainer: \(error)")
        }
    }

    /// 中文注释：makeSourcesViewModel 方法封装当前类型的一段业务或界面行为。
    func makeSourcesViewModel() -> SourcesViewModel {
        let loadBuiltInSourcesUseCase: LoadBuiltInSourcesUseCase = LoadBuiltInSourcesUseCase(
            sourceRepository: self.sourceRepository
        )
        let loadSourcesUseCase: LoadSourcesUseCase = LoadSourcesUseCase(
            sourceRepository: self.sourceRepository
        )
        let addSourceUseCase: AddSourceUseCase = AddSourceUseCase(
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
        let refreshSourceUseCase: RefreshSourceUseCase = RefreshSourceUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser,
            urlResolver: self.urlResolver,
            contentRepository: self.contentRepository
        )
        let listDebugUseCase: ListDebugUseCase = ListDebugUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser,
            urlResolver: self.urlResolver
        )

        return SourcesViewModel(
            loadBuiltInSourcesUseCase: loadBuiltInSourcesUseCase,
            loadSourcesUseCase: loadSourcesUseCase,
            addSourceUseCase: addSourceUseCase,
            deleteSourceUseCase: deleteSourceUseCase,
            updateSourceRuleUseCase: updateSourceRuleUseCase,
            duplicateSourceRuleUseCase: duplicateSourceRuleUseCase,
            exportSourceRulePackageUseCase: exportSourceRulePackageUseCase,
            importSourceRulePackageUseCase: importSourceRulePackageUseCase,
            refreshSourceUseCase: refreshSourceUseCase,
            listDebugUseCase: listDebugUseCase,
            sourceSelectionStore: self.sourceSelectionStore
        )
    }

    /// 中文注释：makeLibraryViewModel 方法封装当前类型的一段业务或界面行为。
    func makeLibraryViewModel() -> LibraryViewModel {
        let loadLibraryUseCase: LoadLibraryUseCase = LoadLibraryUseCase(
            contentRepository: self.contentRepository
        )
        let loadSourcesUseCase: LoadSourcesUseCase = LoadSourcesUseCase(
            sourceRepository: self.sourceRepository
        )
        let toggleFavoriteUseCase: ToggleFavoriteUseCase = ToggleFavoriteUseCase(
            favoriteRepository: self.favoriteRepository
        )
        let recordOpenItemUseCase: RecordOpenItemUseCase = RecordOpenItemUseCase(
            historyRepository: self.historyRepository
        )
        let refreshSourceUseCase: RefreshSourceUseCase = RefreshSourceUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser,
            urlResolver: self.urlResolver,
            contentRepository: self.contentRepository
        )

        return LibraryViewModel(
            loadLibraryUseCase: loadLibraryUseCase,
            loadSourcesUseCase: loadSourcesUseCase,
            toggleFavoriteUseCase: toggleFavoriteUseCase,
            recordOpenItemUseCase: recordOpenItemUseCase,
            refreshSourceUseCase: refreshSourceUseCase,
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
            loadChaptersUseCase: loadChaptersUseCase
        )
    }

    /// 中文注释：makeReaderViewModel 方法封装当前类型的一段业务或界面行为。
    func makeReaderViewModel(
        item: ContentItem,
        source: Source,
        selectedChapter: ChapterLink? = nil
    ) -> ReaderViewModel {
        let loadReaderChapterUseCase: LoadReaderChapterUseCase = LoadReaderChapterUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser
        )

        return ReaderViewModel(
            item: item,
            source: source,
            selectedChapter: selectedChapter,
            loadReaderChapterUseCase: loadReaderChapterUseCase
        )
    }

    /// 中文注释：makeHistoryViewModel 方法封装当前类型的一段业务或界面行为。
    func makeHistoryViewModel() -> HistoryViewModel {
        let loadHistoryUseCase: LoadHistoryUseCase = LoadHistoryUseCase(
            historyRepository: self.historyRepository,
            favoriteRepository: self.favoriteRepository
        )
        let loadLibraryUseCase: LoadLibraryUseCase = LoadLibraryUseCase(
            contentRepository: self.contentRepository
        )
        let loadSourcesUseCase: LoadSourcesUseCase = LoadSourcesUseCase(
            sourceRepository: self.sourceRepository
        )

        return HistoryViewModel(
            loadHistoryUseCase: loadHistoryUseCase,
            loadLibraryUseCase: loadLibraryUseCase,
            loadSourcesUseCase: loadSourcesUseCase
        )
    }
}
