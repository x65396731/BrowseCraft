import Observation
import Combine
import Foundation
@preconcurrency import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime

// 中文注释：LibraryViewModel 负责 Library 当前 source、runtime 刷新、当前快照和列表状态。

/// 中文注释：Library 首次加载只向 App 装配层暴露流程结果，具体错误仍由现有 Library 状态展示。
enum LibraryInitialLoadOutcome: Equatable {
    case noSources
    case loaded
    case failed
    case cancelled
}

/// 中文注释：LibraryViewModel 以 SourceRuntimeKind 作为 Library 展示和刷新入口。
@MainActor
@Observable
final class LibraryViewModel {
    private(set) var items: [ContentItem] = []
    private(set) var sources: [Source] = []
    private(set) var favoriteItemIDs: Set<String> = []
    private(set) var selectedSourceID: String?
    var selectedListTabID: String?
    var errorMessage: String?
    private(set) var selectedListTabErrorMessage: String?
    private(set) var isRefreshing: Bool = false
    private(set) var isLoadingNextPage: Bool = false
    private(set) var preparingSource: SourceLoadingState?
    private(set) var preparedLibrarySnapshot: SourceLibrarySnapshot?
    private(set) var requestedSourceLogin: LibrarySourceLoginState?
    // 中文注释：来源内搜索状态（`BC-SEARCH-007` App 侧）。结果与列表同型，条目点开走同一条详情链。
    private(set) var isPresentingSearch: Bool = false
    var searchKeyword: String = ""
    private(set) var searchResults: [ContentItem] = []
    private(set) var isSearching: Bool = false
    private(set) var searchErrorMessage: String?
    private(set) var hasSearched: Bool = false
    /// 中文注释：提交时定格的关键词（`docs/design/Search-Page-Redesign-Design.md` 第八节）：眉行、无结果、重试都用它，不跟输入框走。
    private(set) var submittedSearchKeyword: String = ""
    /// 搜索结果的下一页：`searchRules[].pagination` 声明、Runtime 报出才有；当前线上规则都不带。
    private(set) var searchNextPage: Int?
    private(set) var searchCurrentPage: Int = 1
    private(set) var isLoadingNextSearchPage: Bool = false
    /// 失败归类为登录墙（`accessRequired` / `protectedResource`）时横幅多一个「登录」。
    private(set) var searchFailureNeedsLogin: Bool = false
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    private(set) var currentListPage: Int = 1
    private(set) var canLoadNextPage: Bool = false
    private var credentialRevision: Int = 0
    /// 中文注释：「上次看到」瓷砖——当前来源最近一条视频历史（`docs/design/Library-Video-Page-Redesign-Design.md` 第六节）。
    /// 属于来源、不属于分类：切来源时重取，切分类不动；没有记录就不出瓷砖。
    private(set) var continueWatchingHistory: VideoWatchHistory?
    /// 点瓷砖直接开全屏播放器，与历史页点行同一条路径。
    var videoPlaybackRoute: VideoPlaybackRoute?
    /// 中文注释：漫画来源的「上次读到」瓷砖——当前来源访问时间最近的一条章节历史
    /// （`docs/design/Library-Comic-Page-Redesign-Design.md` 第六节）。与视频瓷砖同一组刷新时机，两者不会同时有值。
    private(set) var continueReadingHistory: ComicChapterHistory?
    /// 中文注释：封面进度角标「读到 4-2」——按 `comicItemID`（= 列表条目 `item.id`）各取最近一条；与瓷砖同一次读出。
    private(set) var comicReadingProgressByItemID: [String: ComicChapterHistory] = [:]
    /// 中文注释：读书来源的「上次读到 / 上次听到」瓷砖——当前来源访问时间最近的一条读书历史（一书一条）
    /// （`docs/design/Library-Book-Page-Redesign-Design.md` 第六节）；与视频 / 漫画瓷砖同一组刷新时机，三者不会同时有值。
    private(set) var continueReadingBook: BookReadingHistory?
    /// 瓷砖那一本的全书进度（进度表 `totalProgression`）；没有不画进度条。
    private(set) var continueReadingBookProgress: Double?
    /// 行的「读到 · 章节名」——按 `bookItemID`（= 详情地址 = 列表条目 `item.id`）查；与瓷砖同一次读出。
    private(set) var bookReadingHistoryByItemID: [String: BookReadingHistory] = [:]

    private let persistenceCoordinator: LibraryPersistenceCoordinator
    private let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase
    private let searchSourceContentUseCase: SearchSourceContentUseCase?
    private let resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase
    private let contentItemMapper: SourceListContentItemMapper
    private let sourceCredentialStore: SourceCredentialStoring
    private let sourceLoginStateResolver: LibrarySourceLoginStateResolver
    private let sourceSelectionStore: SourceSelectionStore
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let fallbackUserID: String
    private let now: () -> Date
    private let videoPlayerViewModelFactory: (@MainActor (VideoWatchHistory, Source) -> VideoPlayerViewModel)?
    private var cancellables: Set<AnyCancellable> = Set<AnyCancellable>()
    private var listStateStore: LibraryListStateStore = LibraryListStateStore()
    /// 中文注释：启动加载使用共享 Task 合并并发调用，动画层消失不会取消实际网络加载。
    private var initialLoadTask: Task<LibraryInitialLoadOutcome, Never>?
    private var initialLoadOutcome: LibraryInitialLoadOutcome?
    /// 中文注释：刷新令牌用于避免旧 source 的慢请求回写或提前关闭当前 source 的 loading。
    private var refreshToken: Int = 0

    init(
        persistenceCoordinator: LibraryPersistenceCoordinator,
        refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase,
        resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase,
        sourceCredentialStore: SourceCredentialStoring,
        sourceSelectionStore: SourceSelectionStore,
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        searchSourceContentUseCase: SearchSourceContentUseCase? = nil,
        userID: String = AppUser.localDefaultID,
        now: @escaping () -> Date = Date.init,
        videoPlayerViewModelFactory: (@MainActor (VideoWatchHistory, Source) -> VideoPlayerViewModel)? = nil
    ) {
        self.persistenceCoordinator = persistenceCoordinator
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
        self.searchSourceContentUseCase = searchSourceContentUseCase
        self.videoPlayerViewModelFactory = videoPlayerViewModelFactory
        self.resolveLibrarySourcePresentationUseCase = resolveLibrarySourcePresentationUseCase
        self.contentItemMapper = SourceListContentItemMapper()
        self.sourceCredentialStore = sourceCredentialStore
        self.sourceLoginStateResolver = LibrarySourceLoginStateResolver(
            credentialStore: sourceCredentialStore,
            now: now
        )
        self.sourceSelectionStore = sourceSelectionStore
        self.activeAppUser = activeAppUser
        self.fallbackUserID = userID
        self.now = now
        self.selectedSourceID = sourceSelectionStore.selectedSourceID
        self.bindSourceSelection()
    }

    @MainActor
    /// 中文注释：保留旧调用入口；实际加载由 loadIfNeeded 合并，避免启动动画和 Library 页面重复请求。
    func load() async {
        _ = await self.loadIfNeeded()
    }

    @MainActor
    func loadIfNeeded() async -> LibraryInitialLoadOutcome {
        if let initialLoadOutcome: LibraryInitialLoadOutcome = self.initialLoadOutcome {
            return initialLoadOutcome
        }

        if let initialLoadTask: Task<LibraryInitialLoadOutcome, Never> = self.initialLoadTask {
            return await initialLoadTask.value
        }

        let initialLoadTask: Task<LibraryInitialLoadOutcome, Never> = Task { [weak self] in
            guard let self else {
                return .cancelled
            }

            return await self.performInitialLoad()
        }
        self.initialLoadTask = initialLoadTask

        let outcome: LibraryInitialLoadOutcome = await initialLoadTask.value
        self.initialLoadTask = nil
        if outcome != .cancelled {
            self.initialLoadOutcome = outcome
        }
        return outcome
    }

    @MainActor
    func reloadForActiveUserChange() async {
        self.initialLoadTask?.cancel()
        self.initialLoadTask = nil
        self.initialLoadOutcome = nil
        self.refreshToken += 1
        self.isRefreshing = false
        self.isLoadingNextPage = false
        self.items = []
        self.sources = []
        self.favoriteItemIDs = []
        self.selectedListTabID = nil
        self.errorMessage = nil
        self.selectedListTabErrorMessage = nil
        self.requestedSourceLogin = nil
        self.preparedLibrarySnapshot = nil
        self.sourceSelectionStore.preparingSource = nil
        self.sourceSelectionStore.preparedLibrarySnapshot = nil
        self.listStateStore = LibraryListStateStore()
        self.applyListCacheEntry(nil)
        _ = await self.loadIfNeeded()
    }

    @MainActor
    private func performInitialLoad() async -> LibraryInitialLoadOutcome {
        do {
            let snapshot: LibraryPersistenceSnapshot = try await self.persistenceCoordinator.load(
                userID: self.currentUserID,
                selectedSourceID: self.selectedSourceID
            )
            self.sources = snapshot.sources
            self.favoriteItemIDs = snapshot.favoriteItemIDs

            self.restoreStartupLibraryState(snapshot.libraryState)
            // 中文注释：本地读取，不等网络——列表取不到时还能接着看。
            self.refreshContinueWatching()
            if self.applyPreparedSnapshotIfAvailable() == false {
                self.items = []
                self.logLibraryItems(
                    origin: "empty-no-current-snapshot",
                    sourceID: self.selectedSourceID,
                    context: self.selectedListContext
                )
            }
            #if DEBUG
            AppDebugLog.write(
                "[BrowseCraftLibrary] load source=\(self.selectedSourceID ?? "nil") " +
                "items=\(self.items.count) " +
                "context=\(self.contextDescription(self.selectedListContext))"
            )
            #endif

            guard self.selectedSource != nil else {
                return .noSources
            }

            return await self.refreshSelectedListTab()
        } catch is CancellationError {
            return .cancelled
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "library-load-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            return .failed
        }
    }

    @MainActor
    func selectListTab(id tabID: String) async {
        guard self.visibleListTabs.contains(where: { tab in tab.id == tabID }) else {
            self.ensureSelectedListTab()
            return
        }

        if self.selectedListTabID != tabID {
            self.refreshToken += 1
            self.selectedListTabID = tabID
            self.selectedListTabErrorMessage = self.currentListTabErrorMessage()
            self.loadCachedItemsForSelectedTab()
            self.saveCurrentLibraryState(lastRefreshAt: nil)
        }

        // 中文注释：缓存本来就按 tab 分开存，只是此前切过去之后**无条件**再 replace 刷一次，
        // 于是 `tab-cache-hit` 刚显示出来的内容立刻被一次网络取回顶掉（2026-09-20 真机日志：
        // 命中 40 条 → 紧接着 `/browse/13-1.html` 又取一遍）。取到过就不重取，**不设过期时间**；
        // 要新内容由用户自己的刷新动作触发（走 `refreshSelectedListTab`，不受这里影响）。
        if let selectedSourceID: String = self.selectedSourceID,
           self.listStateStore.hasLoaded(
               sourceID: selectedSourceID,
               context: self.selectedListContext
           ) {
            self.logLibraryItems(
                origin: "tab-switch-cached-skip-refresh",
                sourceID: selectedSourceID,
                context: self.selectedListContext
            )
            return
        }

        await self.refreshSelectedListTab()
    }

    @MainActor
    @discardableResult
    func refreshSelectedListTab() async -> LibraryInitialLoadOutcome {
        return await self.loadSelectedListPage(
            page: 1,
            mode: .replace
        )
    }

    /// 中文注释：列表翻页只看 Runtime 报没报下一页，与 kind 无关。
    /// 2026-09-12 之前这里写死 `.video`——漫画列表的 Runtime 已经报出 `nextPage`，UI 却从不去取。
    private var selectedSourceSupportsListPagination: Bool {
        guard let kind: SourceRuntimeKind = self.selectedSource?.configuration.kind else {
            return false
        }
        // 中文注释：2026-09-14 biquhua 模拟器复验——规则已带分页模板、Runtime 报出 nextPage=2，
        // 这里却只认 video / comic，book 的触底哨兵永远不挂。三种按页取的 kind 都要在这里登记。
        return kind == .video || kind == .comic || kind == .book
    }

    @MainActor
    func loadNextPageIfNeeded() async {
        guard self.selectedSourceSupportsListPagination,
              self.items.isEmpty == false,
              self.isLoadingNextPage == false,
              self.isRefreshing == false,
              self.canLoadNextPage else {
            return
        }

        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftLibraryRefresh] event=load-next-page-if-needed " +
            "source=\(self.selectedSourceID ?? "nil") " +
            "currentPage=\(self.currentListPage) " +
            "nextPage=\(self.nextPageForSelectedList.map(String.init) ?? "nil")"
        )
        #endif

        _ = await self.loadNextPage()
    }

    var nextListPage: Int? {
        guard self.selectedSourceSupportsListPagination,
              self.isRefreshing == false,
              self.isLoadingNextPage == false,
              self.canLoadNextPage else {
            return nil
        }
        return self.nextPageForSelectedList
    }

    var shouldShowPaginationStatus: Bool {
        guard self.selectedSourceSupportsListPagination,
              self.items.isEmpty == false || self.isLoadingNextPage else {
            return false
        }

        return self.currentListPage > 1 || self.canLoadNextPage || self.isLoadingNextPage
    }

    var paginationStatusText: String {
        let base: String = String(
            format: NSLocalizedString("library_pagination_page", comment: ""),
            self.currentListPage
        )
        if self.isLoadingNextPage {
            return String(format: NSLocalizedString("library_pagination_loading_next", comment: ""), base)
        }
        if self.canLoadNextPage {
            return String(format: NSLocalizedString("library_pagination_scroll_for_more", comment: ""), base)
        }
        return String(format: NSLocalizedString("library_pagination_end", comment: ""), base)
    }

    private enum ListPageLoadMode {
        case replace
        case append
    }

    @MainActor
    @discardableResult
    private func loadNextPage() async -> LibraryInitialLoadOutcome {
        guard let nextPage: Int = self.nextPageForSelectedList else {
            return .loaded
        }

        return await self.loadSelectedListPage(
            page: nextPage,
            mode: .append
        )
    }

    @MainActor
    @discardableResult
    private func loadSelectedListPage(
        page: Int,
        mode: ListPageLoadMode
    ) async -> LibraryInitialLoadOutcome {
        guard self.selectedSource != nil else {
            return .noSources
        }

        CrashDiagnostics.shared.setRuleStage(.list)
        self.ensureSelectedListTab()
        guard let refreshedSelectedSource: Source = self.selectedSource else {
            return .noSources
        }

        let expectedSourceID: String = refreshedSelectedSource.id
        let expectedTabID: String? = self.selectedListTabID
        let expectedListContext: ListContext? = self.selectedListContext
        let expectedListStateKey: LibraryListStateKey = self.listStateKey(
            sourceID: expectedSourceID,
            context: expectedListContext
        )
        self.setListTabError(nil, sourceID: expectedSourceID, context: expectedListContext)
        self.refreshToken += 1
        let currentRefreshToken: Int = self.refreshToken
        let requestID: Int = currentRefreshToken
        var shouldRefreshReplacementTab: Bool = false
        var outcome: LibraryInitialLoadOutcome = .cancelled
        self.isRefreshing = mode == .replace
        self.isLoadingNextPage = mode == .append
        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftLibraryRefresh] event=start " +
            "requestID=\(requestID) " +
            "source=\(expectedSourceID) " +
            "context=\(self.contextDescription(expectedListContext)) " +
            "page=\(page) " +
            "mode=\(mode == .append ? "append" : "replace")"
        )
        #endif

        do {
            let output: SourceListOutput = try await self.refreshSourceRuntimeUseCase.execute(
                source: refreshedSelectedSource,
                listContext: ListContextTransfer(value: expectedListContext),
                page: page
            )
            if Task.isCancelled == false,
               self.refreshToken == currentRefreshToken,
               self.isCurrentListState(sourceID: expectedSourceID, key: expectedListStateKey) {
                let loadedItems: [ContentItem] = self.contentItemMapper.map(
                    output: output,
                    source: refreshedSelectedSource,
                    context: expectedListContext
                )
                let entry: LibraryListCacheEntry
                switch mode {
                case .replace:
                    entry = self.listStateStore.replaceWithFirstPage(
                        source: refreshedSelectedSource,
                        items: loadedItems,
                        nextPage: output.pagination?.nextPage,
                        context: expectedListContext
                    )
                case .append:
                    entry = self.listStateStore.storePage(
                        source: refreshedSelectedSource,
                        pageNumber: page,
                        items: loadedItems,
                        nextPage: output.pagination?.nextPage,
                        context: expectedListContext
                    )
                }
                // 中文注释：只有真从站点取回才记——读缓存不算。
                self.listStateStore.markLoaded(
                    sourceID: refreshedSelectedSource.id,
                    context: expectedListContext
                )
                self.applyListCacheEntry(entry)
                self.setListTabError(nil, sourceID: expectedSourceID, context: expectedListContext)
                if mode == .replace,
                   self.updateConfirmedEmptyListTab(
                    sourceID: expectedSourceID,
                    tabID: expectedTabID,
                    itemCount: loadedItems.count
                ) {
                    self.ensureSelectedListTab()
                    shouldRefreshReplacementTab = self.selectedListTabID != expectedTabID
                }
                self.sourceSelectionStore.publishLibrarySnapshot(
                    source: refreshedSelectedSource,
                    pages: entry.snapshotPages,
                    listContext: expectedListContext
                )
                self.logLibraryItems(
                    origin: "runtime-refresh-result",
                    sourceID: expectedSourceID,
                    context: expectedListContext,
                    requestID: requestID
                )
                self.saveCurrentLibraryState(lastRefreshAt: self.now())
                #if DEBUG
                let pageState: LibraryListPageState? = entry.pages[page]
                AppDebugLog.write(
                    "[BrowseCraftLibrary] reload after refresh source=\(expectedSourceID) " +
                    "requestID=\(requestID) " +
                    "items=\(self.items.count) " +
                    "pageRawItems=\(pageState?.items.count ?? loadedItems.count) " +
                    "pageAcceptedItems=\(pageState?.visibleItems.count ?? loadedItems.count) " +
                    "pageDuplicateItems=\(pageState?.duplicateCount ?? 0) " +
                    "pageOutcome=\(pageState?.outcome.rawValue ?? "unknown") " +
                    "resolvedPage=\(entry.currentPage) " +
                    "nextPage=\(entry.nextPage.map(String.init) ?? "nil") " +
                    "context=\(self.contextDescription(expectedListContext))"
                )
                #endif
                self.favoriteItemIDs = try await self.persistenceCoordinator.favoriteItemIDs(
                    sourceID: self.selectedSourceID
                )
                outcome = .loaded
            } else {
                #if DEBUG
                AppDebugLog.write(
                    "[BrowseCraftLibraryRefresh] event=stale-result " +
                    "requestID=\(requestID) " +
                    "source=\(expectedSourceID) " +
                    "context=\(self.contextDescription(expectedListContext)) " +
                    "current=\(self.currentListStateKey()?.description ?? "nil")"
                )
                #endif
            }
        } catch is CancellationError {
            // 中文注释：快速切换 source 时取消旧请求；取消结果不能显示为用户错误。
        } catch {
            if self.refreshToken == currentRefreshToken,
               self.isCurrentListState(sourceID: expectedSourceID, key: expectedListStateKey) {
                let event: String = mode == .append ? "library-pagination-error" : "library-refresh-error"
                RuleExecutionErrorClassifier.log(error: error, stage: .list, event: event)
                AppAnalytics.shared.logDiagnosticFailure(kind: RuleExecutionErrorClassifier.diagnosticFailureKind(for: error), stage: .list, errorCode: event)
                if mode == .append {
                    self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
                } else {
                    self.setListTabError(
                        RuleExecutionErrorClassifier.userMessage(for: error),
                        sourceID: expectedSourceID,
                        context: expectedListContext
                    )
                }
                outcome = .failed
            }
        }

        if self.refreshToken == currentRefreshToken,
           mode == .append {
            self.isLoadingNextPage = false
        }

        if self.refreshToken == currentRefreshToken {
            self.isRefreshing = false
        }

        if shouldRefreshReplacementTab,
           self.refreshToken == currentRefreshToken,
           self.selectedSourceID == expectedSourceID {
            return await self.refreshSelectedListTab()
        }

        return outcome
    }

    @MainActor
    /// 中文注释：toggleFavorite 方法封装当前类型的一段业务或界面行为。
    func toggleFavorite(item: ContentItem) async {
        do {
            let wasFavorite: Bool = self.favoriteItemIDs.contains(item.id)
            let source: Source? = self.source(for: item.sourceId)
            self.favoriteItemIDs = try await self.persistenceCoordinator.toggleFavorite(
                LibraryFavoriteMutation(
                    item: item,
                    source: source,
                    favoritedAt: self.now()
                )
            )
            AppAnalytics.shared.logBookmarkChanged(isFavorite: wasFavorite == false, source: source)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "favorite-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    /// 中文注释：sourceName 方法封装当前类型的一段业务或界面行为。
    func sourceName(for sourceId: String) -> String {
        return self.source(for: sourceId)?.name ?? "Unknown Source"
    }

    /// 中文注释：source 方法封装当前类型的一段业务或界面行为。
    func source(for sourceId: String) -> Source? {
        return self.sources.first { source in
            return source.id == sourceId
        }
    }

    var selectedSource: Source? {
        return self.sources.first { source in
            return source.id == self.selectedSourceID
                && source.accessState == .active
        }
    }

    var selectedSourceLoginState: LibrarySourceLoginState? {
        _ = self.credentialRevision
        return self.sourceLoginStateResolver.resolve(source: self.selectedSource)
    }

    @MainActor
    func requestSelectedSourceLogin() {
        self.requestedSourceLogin = self.selectedSourceLoginState
    }

    @MainActor
    func dismissRequestedSourceLogin() {
        self.requestedSourceLogin = nil
    }

    // MARK: - 来源内搜索

    /// 由规则声明：runtime 能力里 `supportsSearch` 为真才显示搜索入口。
    var selectedSourceSupportsSearch: Bool {
        guard let source: Source = self.selectedSource,
              let useCase: SearchSourceContentUseCase = self.searchSourceContentUseCase else {
            return false
        }
        return useCase.supportsSearch(source: source)
    }

    @MainActor
    func presentSearch() {
        guard self.selectedSourceSupportsSearch else {
            return
        }
        self.isPresentingSearch = true
    }

    @MainActor
    func dismissSearch() {
        self.isPresentingSearch = false
    }

    /// 中文注释：提交搜索。连续回车不叠请求——上一次还没回来就取消它、发新的（合同第七节）。
    /// `keyword` 不传就用输入框的字；重试与登录后重搜传定格的 `submittedSearchKeyword`。
    @MainActor
    func performSearch(keyword overrideKeyword: String? = nil) async {
        guard let source: Source = self.selectedSource,
              let useCase: SearchSourceContentUseCase = self.searchSourceContentUseCase else {
            return
        }
        let keyword: String = (overrideKeyword ?? self.searchKeyword).trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false else {
            return
        }
        self.searchTask?.cancel()
        let task: Task<Void, Never> = Task { @MainActor in
            await self.runSearch(source: source, useCase: useCase, keyword: keyword)
        }
        self.searchTask = task
        await task.value
    }

    @MainActor
    private func runSearch(source: Source, useCase: SearchSourceContentUseCase, keyword: String) async {
        self.submittedSearchKeyword = keyword
        self.isSearching = true
        self.searchErrorMessage = nil
        self.searchFailureNeedsLogin = false
        self.searchNextPage = nil
        self.searchCurrentPage = 1
        do {
            let output: SourceListOutput = try await useCase.execute(source: source, keyword: keyword)
            guard Task.isCancelled == false else {
                return
            }
            self.searchResults = self.contentItemMapper.map(output: output, source: source, context: nil)
            self.searchNextPage = output.pagination?.nextPage
        } catch is CancellationError {
            return
        } catch {
            guard Task.isCancelled == false else {
                return
            }
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-search-error")
            self.searchResults = []
            self.searchErrorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            self.searchFailureNeedsLogin = Self.isLoginWall(error)
        }
        self.isSearching = false
        self.hasSearched = true
    }

    /// 失败横幅的「重试」：用定格的关键词重搜。
    @MainActor
    func retrySearch() async {
        await self.performSearch(keyword: self.submittedSearchKeyword)
    }

    /// 中文注释：搜索结果的下一页（合同第六节）：与列表分页同一个触底哨兵，只有 Runtime 报出 `nextPage` 才会被调到。
    @MainActor
    func loadNextSearchPage() async {
        guard let page: Int = self.searchNextPage,
              self.isSearching == false,
              self.isLoadingNextSearchPage == false,
              let source: Source = self.selectedSource,
              let useCase: SearchSourceContentUseCase = self.searchSourceContentUseCase else {
            return
        }
        let keyword: String = self.submittedSearchKeyword
        guard keyword.isEmpty == false else {
            return
        }
        self.isLoadingNextSearchPage = true
        defer {
            self.isLoadingNextSearchPage = false
        }
        do {
            let output: SourceListOutput = try await useCase.execute(source: source, keyword: keyword, page: page)
            let appended: [ContentItem] = self.contentItemMapper.map(output: output, source: source, context: nil)
            let existingIDs: Set<String> = Set(self.searchResults.map(\.id))
            self.searchResults.append(contentsOf: appended.filter { existingIDs.contains($0.id) == false })
            self.searchCurrentPage = page
            self.searchNextPage = output.pagination?.nextPage
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-search-next-page-error")
            self.searchNextPage = nil
        }
    }

    /// 分页脚文案：与列表同一组词条；没有翻过页、也没有下一页时不出脚（返回 nil）。
    var searchPaginationStatusText: String? {
        guard self.searchCurrentPage > 1 || self.searchNextPage != nil || self.isLoadingNextSearchPage else {
            return nil
        }
        let base: String = String(
            format: NSLocalizedString("library_pagination_page", comment: ""),
            self.searchCurrentPage
        )
        if self.isLoadingNextSearchPage {
            return String(format: NSLocalizedString("library_pagination_loading_next", comment: ""), base)
        }
        if self.searchNextPage != nil {
            return String(format: NSLocalizedString("library_pagination_scroll_for_more", comment: ""), base)
        }
        return String(format: NSLocalizedString("library_pagination_end", comment: ""), base)
    }

    /// 中文注释：清空叉与换来源都走这里：回未搜索态，正在飞的请求一并取消。
    @MainActor
    func clearSearch() {
        self.searchTask?.cancel()
        self.searchTask = nil
        self.searchKeyword = ""
        self.submittedSearchKeyword = ""
        self.searchResults = []
        self.isSearching = false
        self.searchErrorMessage = nil
        self.searchFailureNeedsLogin = false
        self.hasSearched = false
        self.searchNextPage = nil
        self.searchCurrentPage = 1
    }

    private static func isLoginWall(_ error: Error) -> Bool {
        switch RuleExecutionErrorClassifier.classified(error) {
        case .accessRequired, .protectedResource:
            return true
        default:
            return false
        }
    }

    @MainActor
    func completeRequestedSourceLogin(credential: SourceCredential) {
        guard credential.sourceID == self.requestedSourceLogin?.sourceID else {
            return
        }

        self.sourceCredentialStore.save(credential)
        self.credentialRevision += 1
        self.requestedSourceLogin = nil

        // 中文注释：搜索页的登录墙（合同第七节）：登录成功后用定格的关键词自动重搜。
        if self.isPresentingSearch && self.searchFailureNeedsLogin {
            Task { @MainActor in
                await self.retrySearch()
            }
        }
    }

    @MainActor
    func removeSelectedSourceCredential() {
        guard let sourceID: String = self.selectedSourceID else {
            return
        }

        self.sourceCredentialStore.removeCredential(sourceID: sourceID)
        self.credentialRevision += 1
        self.requestedSourceLogin = nil
    }

    /// 中文注释：Library 正文的唯一状态轴。判定顺序就是优先级，互斥由 `switch` 保证——
    /// 此前加载态与空态是两条互不知情的 if 链，两边都看 `items.isEmpty`，冷启动必然同时渲染。
    ///
    /// 切源只有在屏上**还留着旧列表**时才走遮罩：遮罩是为了挡住旧数据，不是为了表示正在加载。
    /// 旧列表本来就是空的，就和普通首屏一样走骨架。
    var bodyState: LibraryBodyState {
        if let preparingSource: SourceLoadingState = self.preparingSource {
            return self.items.isEmpty
                ? .loadingFirstPage
                : .switchingSource(sourceName: preparingSource.sourceName)
        }

        if self.items.isEmpty {
            if self.isRefreshing {
                return .loadingFirstPage
            }

            if let selectedListTabErrorMessage: String = self.selectedListTabErrorMessage {
                return .failed(message: selectedListTabErrorMessage)
            }

            return .empty
        }

        return .content
    }

    var listTabStates: [LibraryListTabState] {
        let tabs: [ListTabRule] = self.visibleListTabs
        #if DEBUG
        self.logListTabs(
            origin: "listTabStates",
            source: self.selectedSource,
            tabs: tabs
        )
        #endif
        return tabs.map { tab in
            return LibraryListTabState(
                id: tab.id,
                title: tab.title,
                isSelected: self.selectedListTabID == tab.id
            )
        }
    }

    func imageRequestConfig(for source: Source) -> RequestConfig? {
        return self.resolveLibrarySourcePresentationUseCase.imageRequestConfig(
            for: source,
            listTab: self.selectedListTab
        )
    }

    func primaryActionTitle(for source: Source) -> String {
        if self.shouldOpenReaderDirectly(for: source) {
            return "Read"
        }

        return "Chapters"
    }

    func primaryActionSystemImage(for source: Source) -> String {
        if self.shouldOpenReaderDirectly(for: source) {
            return "book"
        }

        return "list.bullet"
    }

    func shouldOpenReaderDirectly(for source: Source) -> Bool {
        return self.resolveLibrarySourcePresentationUseCase.shouldOpenReaderDirectly(for: source)
    }

    private var listTabs: [ListTabRule] {
        return self.resolveLibrarySourcePresentationUseCase.listTabs(for: self.selectedSource)
    }

    private var visibleListTabs: [ListTabRule] {
        let tabs: [ListTabRule] = self.listTabs
        return self.listStateStore.visibleTabs(tabs, source: self.selectedSource)
    }

    private var selectedListTab: ListTabRule? {
        guard let selectedListTabID: String = self.selectedListTabID else {
            return self.visibleListTabs.first
        }

        return self.visibleListTabs.first { tab in
            return tab.id == selectedListTabID
        } ?? self.visibleListTabs.first
    }

    private func ensureSelectedListTab() {
        let tabs: [ListTabRule] = self.visibleListTabs
        #if DEBUG
        self.logListTabs(
            origin: "ensureSelectedListTab",
            source: self.selectedSource,
            tabs: tabs
        )
        #endif

        if let selectedListTabID: String = self.selectedListTabID,
           tabs.contains(where: { tab in tab.id == selectedListTabID }) {
            return
        }

        self.selectedListTabID = tabs.first?.id
        self.selectedListTabErrorMessage = self.currentListTabErrorMessage()
    }

    private func updateConfirmedEmptyListTab(
        sourceID: String,
        tabID: String?,
        itemCount: Int
    ) -> Bool {
        return self.listStateStore.updateConfirmedEmptyTab(
            sourceID: sourceID,
            tabID: tabID,
            itemCount: itemCount
        )
    }

    private func listStateKey(
        sourceID: String,
        context: ListContext?
    ) -> LibraryListStateKey {
        return self.listStateStore.stateKey(sourceID: sourceID, context: context)
    }

    private func currentListStateKey() -> LibraryListStateKey? {
        guard let selectedSourceID: String = self.selectedSourceID else {
            return nil
        }

        return self.listStateKey(sourceID: selectedSourceID, context: self.selectedListContext)
    }

    private func isCurrentListState(
        sourceID: String,
        key: LibraryListStateKey
    ) -> Bool {
        return self.selectedSourceID == sourceID && self.currentListStateKey() == key
    }

    private func currentListTabErrorMessage() -> String? {
        guard let selectedSourceID: String = self.selectedSourceID else {
            return nil
        }
        return self.listStateStore.errorMessage(
            sourceID: selectedSourceID,
            context: self.selectedListContext
        )
    }

    private func setListTabError(_ message: String?, sourceID: String, context: ListContext?) {
        self.listStateStore.setErrorMessage(message, sourceID: sourceID, context: context)
        if self.isCurrentListState(
            sourceID: sourceID,
            key: self.listStateKey(sourceID: sourceID, context: context)
        ) {
            self.selectedListTabErrorMessage = message
        }
    }

    private func isSelectedDefaultListTab() -> Bool {
        guard let selectedTabID: String = self.selectedListTab?.id,
              let firstTabID: String = self.visibleListTabs.first?.id else {
            return false
        }

        return selectedTabID == firstTabID
    }

    #if DEBUG
    private func logListTabs(
        origin: String,
        source: Source?,
        tabs: [ListTabRule]
    ) {
        let tabDescription: String = tabs.map { tab in
            return [
                tab.id,
                tab.title,
                tab.list.url
            ].joined(separator: "|")
        }
        .joined(separator: ", ")

        AppDebugLog.write(
            "[BrowseCraftLibraryTabs] origin=\(origin) " +
            "source=\(source?.id ?? "nil") " +
            "kind=\(source?.configuration.kind.rawValue ?? "nil") " +
            "selected=\(self.selectedListTabID ?? "nil") " +
            "count=\(tabs.count) " +
            "tabs=[\(tabDescription)]"
        )
    }
    #endif


    private func contextDescription(_ context: ListContext?) -> String {
        guard let context: ListContext = context else {
            return "nil"
        }

        return [
            "page=\(context.pageId ?? "nil")",
            "tab=\(context.tabId ?? "nil")",
            "section=\(context.sectionId ?? "nil")",
            "rule=\(context.listRuleId ?? "nil")"
        ].joined(separator: ",")
    }

    private func bindSourceSelection() {
        self.sourceSelectionStore.$selectedSourceID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedSourceID in
                self?.applySelectedSourceID(selectedSourceID)
            }
            .store(in: &self.cancellables)

        // 中文注释：@Observable 没有 $ 投影，assign(to:) 不再可用；改为 sink 赋值，语义不变。
        self.sourceSelectionStore.$preparingSource
            .receive(on: DispatchQueue.main)
            .sink { [weak self] preparingSource in
                self?.preparingSource = preparingSource
            }
            .store(in: &self.cancellables)

        self.sourceSelectionStore.$preparedLibrarySnapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.applyPreparedLibrarySnapshot(snapshot)
            }
            .store(in: &self.cancellables)
    }

    private func applySelectedSourceID(_ selectedSourceID: String?) {
        if self.selectedSourceID == selectedSourceID {
            return
        }

        self.switchToSource(selectedSourceID)
    }

    private func switchToSource(_ selectedSourceID: String?) {
        // 中文注释：切换 source 时先清除旧 source 的画面状态，避免旧列表在新网站加载期间继续可见。
        self.refreshToken += 1
        self.isRefreshing = false
        self.isLoadingNextPage = false
        self.selectedSourceID = selectedSourceID
        CrashDiagnostics.shared.setSource(selectedSourceID.flatMap { self.source(for: $0) })
        self.selectedListTabID = nil
        self.errorMessage = nil
        self.selectedListTabErrorMessage = nil
        self.requestedSourceLogin = nil
        // 中文注释：上个来源的搜索结果不能留到下个来源的搜索页里（搜索页合同第七节）。
        self.clearSearch()
        self.items = []
        self.ensureSelectedListTab()
        self.applyListCacheEntry(nil)
        self.selectedListTabErrorMessage = self.currentListTabErrorMessage()
        self.saveCurrentLibraryState(lastRefreshAt: nil)

        // 中文注释：优先展示 Sources 入口刚请求到的当前结果；没有当前快照时保持空态，不从持久化缓存补数据。
        if self.applyPreparedSnapshotIfAvailable() == false {
            self.items = []
            self.logLibraryItems(
                origin: "empty-after-source-switch-no-snapshot",
                sourceID: selectedSourceID,
                context: self.selectedListContext
            )
        }
        self.reloadFavoriteItemIDs(event: "switch-source-error")
        self.refreshContinueWatching()
    }

    // MARK: - 「上次看到」瓷砖

    /// 中文注释：重读当前来源的本地历史：视频来源读最近一条视频历史（「上次看到」），漫画来源读全部章节历史
    /// （「上次读到」与封面进度角标）；来源没了、换了、历史被删了都会把它们清掉。
    /// 调用时机：首次加载、切来源、从播放器 / 阅读器 / 详情回来、回到库标签、来源页连带删除历史之后。
    func refreshContinueWatching() {
        guard let source: Source = self.selectedSource else {
            self.continueWatchingHistory = nil
            self.clearComicReadingState()
            self.clearBookReadingState()
            return
        }
        switch source.configuration.kind {
        case .video:
            self.clearComicReadingState()
            self.clearBookReadingState()
        case .comic:
            self.continueWatchingHistory = nil
            self.clearBookReadingState()
            self.refreshComicReading(sourceID: source.id)
            return
        case .book:
            self.continueWatchingHistory = nil
            self.clearComicReadingState()
            self.refreshBookReading(sourceID: source.id)
            return
        default:
            self.continueWatchingHistory = nil
            self.clearComicReadingState()
            self.clearBookReadingState()
            return
        }
        let expectedSourceID: String = source.id
        let userID: String = self.currentUserID
        Task {
            do {
                let history: VideoWatchHistory? = try await self.persistenceCoordinator.latestVideoHistory(
                    userID: userID,
                    sourceID: expectedSourceID
                )
                guard self.selectedSourceID == expectedSourceID else {
                    return
                }
                self.continueWatchingHistory = history
            } catch {
                // 中文注释：瓷砖是附加信息，读不到就不出，不弹错。
                RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "library-continue-watching-error")
                self.continueWatchingHistory = nil
            }
        }
    }

    private func refreshComicReading(sourceID expectedSourceID: String) {
        let userID: String = self.currentUserID
        Task {
            do {
                let histories: [ComicChapterHistory] = try await self.persistenceCoordinator.comicChapterHistories(
                    userID: userID,
                    sourceID: expectedSourceID
                )
                guard self.selectedSourceID == expectedSourceID else {
                    return
                }
                // 中文注释：仓储已按访问时间倒序，第一次见到的作品就是它最近读的那一章。
                var latestByItemID: [String: ComicChapterHistory] = [:]
                for history in histories where latestByItemID[history.comicItemID] == nil {
                    latestByItemID[history.comicItemID] = history
                }
                self.continueReadingHistory = histories.first
                self.comicReadingProgressByItemID = latestByItemID
            } catch {
                // 中文注释：瓷砖与角标是附加信息，读不到就不出，不弹错。
                RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "library-continue-reading-error")
                self.clearComicReadingState()
            }
        }
    }

    private func clearComicReadingState() {
        self.continueReadingHistory = nil
        self.comicReadingProgressByItemID = [:]
    }

    private func refreshBookReading(sourceID expectedSourceID: String) {
        let userID: String = self.currentUserID
        Task {
            do {
                let histories: [BookReadingHistory] = try await self.persistenceCoordinator.bookReadingHistories(
                    userID: userID,
                    sourceID: expectedSourceID
                )
                // 中文注释：进度条只给瓷砖那一本读一次，不逐行查。
                var progression: Double? = nil
                if let latest: BookReadingHistory = histories.first {
                    progression = try await self.persistenceCoordinator.bookReadingProgression(
                        userID: userID,
                        sourceID: expectedSourceID,
                        detailURL: latest.detailURL
                    )
                }
                guard self.selectedSourceID == expectedSourceID else {
                    return
                }
                var byItemID: [String: BookReadingHistory] = [:]
                for history in histories where byItemID[history.bookItemID] == nil {
                    byItemID[history.bookItemID] = history
                }
                self.continueReadingBook = histories.first
                self.continueReadingBookProgress = progression.map { min(1, max(0, $0)) }
                self.bookReadingHistoryByItemID = byItemID
            } catch {
                // 中文注释：瓷砖与「读到哪」是附加信息，读不到就不出，不弹错。
                RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "library-continue-reading-book-error")
                self.clearBookReadingState()
            }
        }
    }

    private func clearBookReadingState() {
        self.continueReadingBook = nil
        self.continueReadingBookProgress = nil
        self.bookReadingHistoryByItemID = [:]
    }

    /// 整站是否有声：reader 规则全是 audio（书籍库合同第二节）；眉行、封面耳机与「听」措辞都看它。
    var isAudiobookSource: Bool {
        guard let source: Source = self.selectedSource else {
            return false
        }
        return self.resolveLibrarySourcePresentationUseCase.isAudiobookSource(for: source)
    }

    /// 历史里的章节名照原文（去首尾空白），空为 nil——各站编号形式不一，不缩成「第 N 章」。
    static func bookChapterTitle(of history: BookReadingHistory) -> String? {
        guard let title: String = history.chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              title.isEmpty == false else {
            return nil
        }
        return title
    }

    /// 行的第三行「读到 · 章节名」（整站有声「听到 · 章节名」）；没读过或历史里没有章节名为 nil。
    func bookReadToText(for item: ContentItem) -> String? {
        guard let history: BookReadingHistory = self.bookReadingHistoryByItemID[item.id],
              let chapter: String = Self.bookChapterTitle(of: history) else {
            return nil
        }
        let key: String = self.isAudiobookSource ? "library_book_listened_to" : "library_book_read_to"
        return String(format: NSLocalizedString(key, comment: ""), chapter)
    }

    /// 长按「继续读 / 继续听」用的历史；这本没读过为 nil。没有章节名也能开——阅读器按续读位置接着。
    func bookContinueHistory(for item: ContentItem) -> BookReadingHistory? {
        return self.bookReadingHistoryByItemID[item.id]
    }

    /// 长按菜单文案：「继续读 · 第312章 山雨欲來」，历史里没有章节名时只写「继续读」；整站有声换「听」。
    func bookContinueMenuTitle(for history: BookReadingHistory) -> String {
        let audio: Bool = self.isAudiobookSource
        if let chapter: String = Self.bookChapterTitle(of: history) {
            return String(
                format: NSLocalizedString(audio ? "library_card_continue_listening" : "library_card_continue_reading", comment: ""),
                chapter
            )
        }
        return NSLocalizedString(audio ? "history_menu_continue_listening" : "history_menu_continue_reading", comment: "")
    }

    /// 瓷砖第三行：章节名原文；没有这行不出。
    var continueReadingBookChapterText: String? {
        return self.continueReadingBook.flatMap(Self.bookChapterTitle(of:))
    }

    /// 瓷砖底行只写时刻，与视频、漫画瓷砖同一取法。
    var continueReadingBookTimeText: String? {
        return self.continueReadingBook.map { self.tileTimeText(for: $0.visitedAt) }
    }

    /// 章节名缩成编号：「第4話(2) 真夜中の逢瀬」→「4-2」；解不出数字就用原章节名。
    static func comicChapterLabel(for history: ComicChapterHistory) -> String {
        let title: String = history.chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return ComicChapterTitleParser.parse(title).numberLabel ?? title
    }

    /// 封面角标「读到 4-2」；这部没读过为 nil。
    func comicProgressBadgeText(for item: ContentItem) -> String? {
        guard let history: ComicChapterHistory = self.comicReadingProgressByItemID[item.id] else {
            return nil
        }
        let label: String = Self.comicChapterLabel(for: history)
        guard label.isEmpty == false else {
            return nil
        }
        return String(format: NSLocalizedString("library_comic_read_to", comment: ""), label)
    }

    /// 长按菜单「继续读」用的那条历史；这部没读过或历史里没有能打开的地址为 nil。
    func comicContinueHistory(for item: ContentItem) -> ComicChapterHistory? {
        guard let history: ComicChapterHistory = self.comicReadingProgressByItemID[item.id],
              history.lastReaderPageURL != nil || history.chapterURL != nil else {
            return nil
        }
        return history
    }

    /// 瓷砖第三行「4-2 真夜中の逢瀬 · 6 / 58 页」；没有页数时「第 6 页」。
    var continueReadingProgressText: String? {
        guard let history: ComicChapterHistory = self.continueReadingHistory else {
            return nil
        }
        var parts: [String] = []
        let title: String = history.chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed: ComicChapterTitleParser.ParsedTitle = ComicChapterTitleParser.parse(title)
        if let numberLabel: String = parsed.numberLabel {
            parts.append(parsed.name.isEmpty ? numberLabel : "\(numberLabel) \(parsed.name)")
        } else if title.isEmpty == false {
            parts.append(title)
        }
        if let progress: String = ComicDetailViewModel.pageProgressText(
            pageIndex: history.lastPageIndex,
            pageCount: history.pageCount
        ) {
            parts.append(progress)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 瓷砖进度条（有页数时）。
    var continueReadingProgress: Double? {
        guard let history: ComicChapterHistory = self.continueReadingHistory,
              let pageIndex: Int = history.lastPageIndex, pageIndex >= 0,
              let pageCount: Int = history.pageCount, pageCount > 0 else {
            return nil
        }
        return min(1, max(0, Double(pageIndex + 1) / Double(pageCount)))
    }

    /// 瓷砖底行只写时刻，与视频瓷砖同一取法。
    var continueReadingTimeText: String? {
        return self.continueReadingHistory.map { self.tileTimeText(for: $0.visitedAt) }
    }

    /// 点瓷砖：用历史记录直接开播放器，与历史页 `openVideoHistory` 同一条路径。
    @MainActor
    func openContinueWatching() {
        guard let history: VideoWatchHistory = self.continueWatchingHistory,
              let source: Source = self.selectedSource,
              let factory: @MainActor (VideoWatchHistory, Source) -> VideoPlayerViewModel = self.videoPlayerViewModelFactory else {
            return
        }
        self.videoPlaybackRoute = VideoPlaybackRoute(
            id: history.id,
            viewModel: factory(history, source)
        )
    }

    /// 瓷砖第三行「第 12 集 · 看到 23:14 / 45:00」，与历史页同一套取法。
    var continueWatchingProgressText: String? {
        return self.continueWatchingHistory.flatMap { HistoryViewModel.videoProgressText(for: $0) }
    }

    /// 瓷砖进度条（知道时长时）。
    var continueWatchingProgress: Double? {
        return self.continueWatchingHistory.flatMap { HistoryViewModel.playbackProgress(for: $0) }
    }

    /// 瓷砖底行只写时刻：「今天 21:30」「昨天 09:12」，更早的只写日期——来源名已是大标题，不重复。
    var continueWatchingTimeText: String? {
        return self.continueWatchingHistory.map { self.tileTimeText(for: $0.updatedAt) }
    }

    private func tileTimeText(for date: Date) -> String {
        let now: Date = self.now()
        let calendar: Calendar = .current
        let day: CatalogPersonalTimeline.Day = CatalogPersonalTimeline.day(for: date, now: now, calendar: calendar)
        let dayText: String = CatalogDayTitle.text(for: day, now: now, calendar: calendar)
        switch day {
        case .today, .yesterday:
            return dayText + " " + date.formatted(date: .omitted, time: .shortened)
        case .date, .unknown:
            return dayText
        }
    }

    /// 眉行里的主机名：去掉 `www.`，与目录卡片同一取法。
    var selectedSourceHostText: String? {
        guard let source: Source = self.selectedSource else {
            return nil
        }
        return CatalogDisplayText.displayHost(CatalogDisplayText.addressParts(of: source.baseURL).host)
    }

    private func applyPreparedLibrarySnapshot(_ snapshot: SourceLibrarySnapshot?) {
        self.preparedLibrarySnapshot = snapshot

        if let snapshot: SourceLibrarySnapshot = snapshot {
            self.upsertSource(snapshot.source)
            if self.selectedSourceID == snapshot.sourceID {
                self.ensureSelectedListTab()
            }
        }

        guard self.applyPreparedSnapshotIfAvailable() else {
            return
        }

        self.reloadFavoriteItemIDs(event: "snapshot-favorite-load-error")
    }

    private func applyPreparedSnapshotIfAvailable() -> Bool {
        guard let snapshot: SourceLibrarySnapshot = self.preparedLibrarySnapshot,
              snapshot.sourceID == self.selectedSourceID,
              self.snapshotMatchesSelectedListContext(snapshot) else {
            return false
        }

        self.upsertSource(snapshot.source)
        let cacheContext: ListContext? = snapshot.listContext ?? self.selectedListContext
        let existingEntry: LibraryListCacheEntry? = self.listStateStore.cachedEntry(
            sourceID: snapshot.sourceID,
            context: cacheContext
        )
        if existingEntry?.snapshotPages != snapshot.pages {
            // 中文注释：外部页面快照是这个列表的新世代；旧请求不能继续向新快照追加数据。
            self.refreshToken += 1
            self.isRefreshing = false
            self.isLoadingNextPage = false
        }
        let entry: LibraryListCacheEntry = self.listStateStore.cacheSnapshot(
            source: snapshot.source,
            pages: snapshot.pages,
            context: cacheContext
        )
        self.applyListCacheEntry(entry)
        self.setListTabError(nil, sourceID: snapshot.sourceID, context: self.selectedListContext)
        self.logLibraryItems(
            origin: "current-snapshot",
            sourceID: snapshot.sourceID,
            context: self.selectedListContext
        )
        return true
    }

    private func snapshotMatchesSelectedListContext(_ snapshot: SourceLibrarySnapshot) -> Bool {
        guard let selectedContext: ListContext = self.selectedListContext else {
            return snapshot.listContext == nil && snapshot.items.first?.listContext == nil
        }

        guard let snapshotContext: ListContext = snapshot.listContext ?? snapshot.items.first?.listContext else {
            return self.isSelectedDefaultListTab()
        }

        return snapshotContext == selectedContext
    }

    private func upsertSource(_ source: Source) {
        if let index: Array<Source>.Index = self.sources.firstIndex(where: { existingSource in
            return existingSource.id == source.id
        }) {
            self.sources[index] = source
            return
        }

        self.sources.insert(source, at: 0)
    }

    private func loadCachedItemsForSelectedTab() {
        if self.applyPreparedSnapshotIfAvailable() == false {
            if let selectedSourceID: String = self.selectedSourceID,
               let cacheEntry: LibraryListCacheEntry = self.listStateStore.cachedEntry(
                   sourceID: selectedSourceID,
                   context: self.selectedListContext
               ) {
                self.applyListCacheEntry(cacheEntry)
                self.setListTabError(nil, sourceID: cacheEntry.sourceID, context: cacheEntry.context)
                self.logLibraryItems(
                    origin: "tab-cache-hit",
                    sourceID: cacheEntry.sourceID,
                    context: cacheEntry.context
                )
                return
            }

            self.applyListCacheEntry(nil)
            self.logLibraryItems(
                origin: "tab-switch-no-snapshot-clear-current",
                sourceID: self.selectedSourceID,
                context: self.selectedListContext
            )
        }
    }

    private var selectedListContext: ListContext? {
        return self.resolveLibrarySourcePresentationUseCase.listContext(from: self.selectedListTab)
    }

    private func restoreStartupLibraryState(_ persistedState: UserLibraryState?) {
        let persistedSource: Source? = persistedState.flatMap { state in
            guard let selectedSourceID: String = state.selectedSourceID else {
                return nil
            }

            return self.source(for: selectedSourceID).flatMap { source in
                return source.accessState == .active ? source : nil
            }
        }
        let resolvedSource: Source? = persistedSource ??
            self.sources.first(where: { source in
                return source.accessState == .active
            })

        guard let source: Source = resolvedSource else {
            self.selectedSourceID = nil
            self.sourceSelectionStore.selectedSourceID = nil
            self.selectedListTabID = nil
            self.items = []
            return
        }

        self.selectedSourceID = source.id
        self.sourceSelectionStore.selectedSourceID = source.id
        CrashDiagnostics.shared.setSource(source)

        if persistedSource?.id == source.id {
            self.restoreSelectedListTab(from: persistedState?.listContext)
        } else {
            self.selectedListTabID = nil
            self.ensureSelectedListTab()
            self.saveCurrentLibraryState(lastRefreshAt: nil)
        }
    }

    private func restoreSelectedListTab(from context: ListContext?) {
        guard let context: ListContext = context else {
            self.selectedListTabID = nil
            self.ensureSelectedListTab()
            self.restoreSelectedListState()
            return
        }

        let tabs: [ListTabRule] = self.listTabs
        self.selectedListTabID = tabs.first { tab in
            let tabContext: ListContext? = self.resolveLibrarySourcePresentationUseCase.listContext(from: tab)
            return tabContext == context ||
                tab.id == context.tabId ||
                tab.list.id == context.listRuleId
        }?.id
        self.ensureSelectedListTab()
        self.restoreSelectedListState()

        if self.selectedListContext != context {
            self.saveCurrentLibraryState(lastRefreshAt: nil)
        }
    }

    private var nextPageForSelectedList: Int? {
        guard let selectedSourceID: String = self.selectedSourceID else {
            return nil
        }

        return self.listStateStore.cachedEntry(
            sourceID: selectedSourceID,
            context: self.selectedListContext
        )?.nextPage
    }

    private func restoreSelectedListState() {
        guard let selectedSourceID: String = self.selectedSourceID else {
            self.applyListCacheEntry(nil)
            return
        }

        let entry: LibraryListCacheEntry? = self.listStateStore.cachedEntry(
            sourceID: selectedSourceID,
            context: self.selectedListContext
        )
        self.applyListCacheEntry(entry)
    }

    private func applyListCacheEntry(_ entry: LibraryListCacheEntry?) {
        self.items = entry?.items ?? []
        self.currentListPage = entry?.currentPage ?? 1
        self.canLoadNextPage = entry?.nextPage != nil
    }

    private func saveCurrentLibraryState(lastRefreshAt: Date?) {
        guard let selectedSourceID: String = self.selectedSourceID else {
            return
        }

        let state: UserLibraryState = UserLibraryState(
            userID: self.currentUserID,
            selectedSourceID: selectedSourceID,
            listContext: self.selectedListContext,
            lastRefreshAt: lastRefreshAt,
            updatedAt: self.now()
        )

        Task {
            do {
                try await self.persistenceCoordinator.save(
                    UserLibraryStateTransfer(value: state)
                )
            } catch {
                AppLog.error(
                    .app,
                    event: "library-state-save-failed",
                    metadata: [
                        "sourceID": selectedSourceID,
                        "error": AppLog.safeErrorCode(error)
                    ]
                )
            }
        }
    }

    /// 中文注释：收藏集合在别的页面被改动（收藏页取消 / 撤销收藏）后，让封面上的爱心状态跟上。
    func refreshFavoriteItemIDs() {
        self.reloadFavoriteItemIDs(event: "favorites-page-change")
    }

    private func reloadFavoriteItemIDs(event: String) {
        let expectedSourceID: String? = self.selectedSourceID
        Task {
            do {
                let favoriteItemIDs: Set<String> = try await self.persistenceCoordinator
                    .favoriteItemIDs(sourceID: expectedSourceID)
                guard self.selectedSourceID == expectedSourceID else {
                    return
                }
                self.favoriteItemIDs = favoriteItemIDs
            } catch {
                RuleExecutionErrorClassifier.log(error: error, stage: .list, event: event)
                AppAnalytics.shared.logDiagnosticFailure(
                    kind: RuleExecutionErrorClassifier.diagnosticFailureKind(for: error),
                    stage: .list,
                    errorCode: event
                )
                self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            }
        }
    }

    private var currentUserID: String {
        return self.activeAppUser?.currentUserID.uuidString ?? self.fallbackUserID
    }

    private func logLibraryItems(
        origin: String,
        sourceID: String?,
        context: ListContext?,
        requestID: Int? = nil
    ) {
        #if DEBUG
        let requestDescription: String = requestID.map { " requestID=\($0)" } ?? ""
        AppDebugLog.write(
            "[BrowseCraftLibraryData] origin=\(origin) " +
            "source=\(sourceID ?? "nil") " +
            "\(requestDescription) " +
            "items=\(self.items.count) " +
            "firstItem=\(self.items.first?.id ?? "nil") " +
            "context=\(self.contextDescription(context))"
        )
        #endif
    }

}
