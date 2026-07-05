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
    private let sourceRuntimeFactory: SourceRuntimeFactory
    private let sourceSelectionStore: SourceSelectionStore

    init() {
        do {
            let database: AppDatabase = try AppDatabase()
            let urlResolver: URLResolvingService = URLResolvingService()
            let httpClient: HTTPClient = AlamofireHTTPClient()
            let pageContentLoader: PageContentLoader = DefaultPageContentLoader(httpClient: httpClient)
            let ruleParser: RuleParsingService = SwiftSoupRuleParser(urlResolver: urlResolver)
            let contentRepository: ContentRepository = GRDBContentRepository(database: database)

            self.database = database
            self.sourceRepository = GRDBSourceRepository(database: database)
            self.contentRepository = contentRepository
            self.favoriteRepository = GRDBFavoriteRepository(database: database)
            self.historyRepository = GRDBHistoryRepository(database: database)
            self.httpClient = httpClient
            self.pageContentLoader = pageContentLoader
            self.urlResolver = urlResolver
            self.ruleParser = ruleParser
            self.sourceRuntimeFactory = SourceRuntimeFactory(
                pageContentLoader: pageContentLoader,
                ruleParser: ruleParser,
                urlResolver: urlResolver,
                contentRepository: contentRepository
            )
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
        let addRuleSourceUseCase: AddRuleSourceUseCase = AddRuleSourceUseCase(
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
        let sourceImportRecommendationUseCase: SourceImportRecommendationUseCase = SourceImportRecommendationUseCase()
        let refreshSourceUseCase: RefreshSourceUseCase = RefreshSourceUseCase(
            pageContentLoader: self.pageContentLoader,
            ruleParser: self.ruleParser,
            urlResolver: self.urlResolver,
            contentRepository: self.contentRepository
        )
        let ruleCandidateAnalyzer: RuleCandidateAnalyzingService = SwiftSoupRuleCandidateAnalyzer()
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
            loadBuiltInSourcesUseCase: loadBuiltInSourcesUseCase,
            loadSourcesUseCase: loadSourcesUseCase,
            addRuleSourceUseCase: addRuleSourceUseCase,
            deleteSourceUseCase: deleteSourceUseCase,
            updateSourceRuleUseCase: updateSourceRuleUseCase,
            duplicateSourceRuleUseCase: duplicateSourceRuleUseCase,
            exportSourceRulePackageUseCase: exportSourceRulePackageUseCase,
            importSourceRulePackageUseCase: importSourceRulePackageUseCase,
            sourceImportRecommendationUseCase: sourceImportRecommendationUseCase,
            refreshSourceUseCase: refreshSourceUseCase,
            listDebugUseCase: listDebugUseCase,
            searchDebugUseCase: searchDebugUseCase,
            detailDebugUseCase: detailDebugUseCase,
            readerDebugUseCase: readerDebugUseCase,
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
        let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase = RefreshSourceRuntimeUseCase(
            runtimeResolver: self.makeSourceRuntimeResolver()
        )

        return LibraryViewModel(
            loadLibraryUseCase: loadLibraryUseCase,
            loadSourcesUseCase: loadSourcesUseCase,
            toggleFavoriteUseCase: toggleFavoriteUseCase,
            recordOpenItemUseCase: recordOpenItemUseCase,
            refreshSourceRuntimeUseCase: refreshSourceRuntimeUseCase,
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
            loadReaderChapterUseCase: loadReaderChapterUseCase,
            resolveReaderSourcePresentationUseCase: ResolveReaderSourcePresentationUseCase()
        )
    }

    /// 中文注释：P3 runtime 工厂入口；Library list refresh 已通过 resolver 试点接入。
    func makeRuleSourceRuntime(source: Source) -> RuleSourceRuntime {
        return self.sourceRuntimeFactory.makeRuleSourceRuntime(source: source)
    }

    func makeSourceRuntimeResolver() -> any SourceRuntimeResolving {
        return self.sourceRuntimeFactory.makeRuntimeResolver()
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
