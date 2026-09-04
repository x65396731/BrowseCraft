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
    private(set) var currentListPage: Int = 1
    private(set) var canLoadNextPage: Bool = false
    private var credentialRevision: Int = 0

    private let persistenceCoordinator: LibraryPersistenceCoordinator
    private let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase
    private let resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase
    private let contentItemMapper: SourceListContentItemMapper
    private let sourceCredentialStore: SourceCredentialStoring
    private let sourceLoginStateResolver: LibrarySourceLoginStateResolver
    private let sourceSelectionStore: SourceSelectionStore
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let fallbackUserID: String
    private let now: () -> Date
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
        userID: String = AppUser.localDefaultID,
        now: @escaping () -> Date = Date.init
    ) {
        self.persistenceCoordinator = persistenceCoordinator
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
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

    @MainActor
    func loadNextPageIfNeeded() async {
        guard self.selectedSource?.configuration.kind == .video,
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
        guard self.selectedSource?.configuration.kind == .video,
              self.isRefreshing == false,
              self.isLoadingNextPage == false,
              self.canLoadNextPage else {
            return nil
        }
        return self.nextPageForSelectedList
    }

    var shouldShowPaginationStatus: Bool {
        guard self.selectedSource?.configuration.kind == .video,
              self.items.isEmpty == false || self.isLoadingNextPage else {
            return false
        }

        return self.currentListPage > 1 || self.canLoadNextPage || self.isLoadingNextPage
    }

    var paginationStatusText: String {
        let base: String = "第 \(self.currentListPage) 页"
        if self.isLoadingNextPage {
            return "\(base) · 正在加载下一页"
        }
        if self.canLoadNextPage {
            return "\(base) · 滑到底部继续加载"
        }
        return "\(base) · 已加载到底"
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
                AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .list, errorCode: event)
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

    @MainActor
    func completeRequestedSourceLogin(credential: SourceCredential) {
        guard credential.sourceID == self.requestedSourceLogin?.sourceID else {
            return
        }

        self.sourceCredentialStore.save(credential)
        self.credentialRevision += 1
        self.requestedSourceLogin = nil
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

    var isShowingSourceLoading: Bool {
        if self.preparingSource != nil {
            return true
        }

        return self.isRefreshing && self.items.isEmpty
    }

    var loadingTitle: String {
        if self.preparingSource?.runtimeKind == .rss || self.selectedSource?.configuration.kind == .rss {
            return "Loading RSS"
        }

        if self.preparingSource != nil {
            return "Loading Source"
        }

        return "Loading Tab"
    }

    var loadingMessage: String {
        if let preparingSource: SourceLoadingState = self.preparingSource {
            return "Fetching the latest items from \(preparingSource.sourceName)."
        }

        return "Fetching the latest items for this tab."
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
                    error: error,
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
