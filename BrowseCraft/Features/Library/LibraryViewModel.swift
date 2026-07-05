import Combine
import Foundation
import BrowseCraftCore

// 中文注释：LibraryViewModel 负责 Library 当前 source、runtime 刷新、当前快照和列表状态。

struct LibraryListTabState: Identifiable, Hashable {
    let id: String
    let title: String
    let isSelected: Bool
}

/// 中文注释：LibraryViewModel 以 SourceRuntimeKind 作为 Library 展示和刷新入口。
final class LibraryViewModel: ObservableObject {
    @Published private(set) var items: [ContentItem] = []
    @Published private(set) var sources: [Source] = []
    @Published private(set) var favoriteItemIDs: Set<String> = []
    @Published private(set) var selectedSourceID: String?
    @Published var selectedListTabID: String?
    @Published var errorMessage: String?
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var preparingSource: SourceLoadingState?
    @Published private(set) var preparedLibrarySnapshot: SourceLibrarySnapshot?

    private let loadBuiltInSourcesUseCase: LoadBuiltInSourcesUseCase
    private let loadSourcesUseCase: LoadSourcesUseCase
    private let toggleFavoriteUseCase: ToggleFavoriteUseCase
    private let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase
    private let loadUserLibraryStateUseCase: LoadUserLibraryStateUseCase
    private let saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase
    private let resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase
    private let sourceSelectionStore: SourceSelectionStore
    private let userID: String
    private let now: () -> Date
    private var cancellables: Set<AnyCancellable> = Set<AnyCancellable>()
    /// 中文注释：刷新令牌用于避免旧 source 的慢请求回写或提前关闭当前 source 的 loading。
    private var refreshToken: Int = 0

    init(
        loadBuiltInSourcesUseCase: LoadBuiltInSourcesUseCase,
        loadSourcesUseCase: LoadSourcesUseCase,
        toggleFavoriteUseCase: ToggleFavoriteUseCase,
        refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase,
        loadUserLibraryStateUseCase: LoadUserLibraryStateUseCase,
        saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase,
        resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase,
        sourceSelectionStore: SourceSelectionStore,
        userID: String = AppUser.localDefaultID,
        now: @escaping () -> Date = Date.init
    ) {
        self.loadBuiltInSourcesUseCase = loadBuiltInSourcesUseCase
        self.loadSourcesUseCase = loadSourcesUseCase
        self.toggleFavoriteUseCase = toggleFavoriteUseCase
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
        self.loadUserLibraryStateUseCase = loadUserLibraryStateUseCase
        self.saveUserLibraryStateUseCase = saveUserLibraryStateUseCase
        self.resolveLibrarySourcePresentationUseCase = resolveLibrarySourcePresentationUseCase
        self.sourceSelectionStore = sourceSelectionStore
        self.userID = userID
        self.now = now
        self.selectedSourceID = sourceSelectionStore.selectedSourceID
        self.bindSourceSelection()
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() async {
        do {
            try self.loadBuiltInSourcesUseCase.execute()
            self.sources = try self.loadSourcesUseCase.execute()
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.loadFavoriteItemIDs()

            try self.restoreStartupLibraryState()
            if self.applyPreparedSnapshotIfAvailable() == false {
                self.items = []
                self.logLibraryItems(
                    origin: "empty-no-current-snapshot",
                    sourceID: self.selectedSourceID,
                    context: self.selectedListContext
                )
            }
            #if DEBUG
            print(
                "[BrowseCraftLibrary] load source=\(self.selectedSourceID ?? "nil") " +
                "items=\(self.items.count) " +
                "context=\(self.contextDescription(self.selectedListContext))"
            )
            #endif

            await self.refreshSelectedListTab()
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "library-load-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    @MainActor
    func selectListTab(id tabID: String) async {
        if self.isRefreshing {
            return
        }

        guard self.listTabs.contains(where: { tab in tab.id == tabID }) else {
            self.ensureSelectedListTab()
            return
        }

        if self.selectedListTabID != tabID {
            self.selectedListTabID = tabID
            self.loadCachedItemsForSelectedTab()
            self.saveCurrentLibraryState(lastRefreshAt: nil)
        }

        await self.refreshSelectedListTab()
    }

    @MainActor
    func refreshSelectedListTab() async {
        guard let selectedSource: Source = self.selectedSource else {
            return
        }

        self.ensureSelectedListTab()
        let expectedSourceID: String = selectedSource.id
        let expectedTabID: String? = self.selectedListTab?.id
        let expectedListContext: ListContext? = self.selectedListContext
        self.refreshToken += 1
        let currentRefreshToken: Int = self.refreshToken
        self.isRefreshing = true

        do {
            let output: SourceListOutput = try await self.refreshSourceRuntimeUseCase.execute(
                source: selectedSource,
                listContext: expectedListContext
            )
            if Task.isCancelled == false,
               self.refreshToken == currentRefreshToken,
               self.selectedSourceID == expectedSourceID,
               self.selectedListTab?.id == expectedTabID {
                self.items = self.contentItems(
                    from: output,
                    source: selectedSource,
                    context: expectedListContext
                )
                self.sourceSelectionStore.publishLibrarySnapshot(
                    source: selectedSource,
                    items: self.items
                )
                self.logLibraryItems(
                    origin: "runtime-refresh-result",
                    sourceID: expectedSourceID,
                    context: expectedListContext
                )
                self.saveCurrentLibraryState(lastRefreshAt: self.now())
                #if DEBUG
                print(
                    "[BrowseCraftLibrary] reload after refresh source=\(expectedSourceID) " +
                    "items=\(self.items.count) " +
                    "context=\(self.contextDescription(expectedListContext))"
                )
                #endif
                self.favoriteItemIDs = try self.toggleFavoriteUseCase.loadFavoriteItemIDs()
            }
        } catch is CancellationError {
            // 中文注释：快速切换 source 时取消旧请求；取消结果不能显示为用户错误。
        } catch {
            if self.refreshToken == currentRefreshToken,
               self.selectedSourceID == expectedSourceID,
               self.selectedListTab?.id == expectedTabID {
                RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "library-refresh-error")
                self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            }
        }

        if self.refreshToken == currentRefreshToken {
            self.isRefreshing = false
        }
    }

    @MainActor
    /// 中文注释：toggleFavorite 方法封装当前类型的一段业务或界面行为。
    func toggleFavorite(item: ContentItem) {
        do {
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.execute(itemId: item.id)
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
        }
    }

    var isShowingSourceLoading: Bool {
        return self.isRefreshing || self.preparingSource != nil
    }

    var loadingTitle: String {
        if self.preparingSource?.runtimeKind == .rss || self.selectedSource?.configuration.kind == .rss {
            return "Loading RSS"
        }

        return "Loading Source"
    }

    var loadingMessage: String {
        if let preparingSource: SourceLoadingState = self.preparingSource {
            return "Fetching the latest items from \(preparingSource.sourceName)."
        }

        return "Fetching the latest items from this source."
    }

    var listTabStates: [LibraryListTabState] {
        return self.listTabs.map { tab in
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

    private var selectedListTab: ListTabRule? {
        guard let selectedListTabID: String = self.selectedListTabID else {
            return self.listTabs.first
        }

        return self.listTabs.first { tab in
            return tab.id == selectedListTabID
        } ?? self.listTabs.first
    }

    private func ensureSelectedListTab() {
        let tabs: [ListTabRule] = self.listTabs

        if let selectedListTabID: String = self.selectedListTabID,
           tabs.contains(where: { tab in tab.id == selectedListTabID }) {
            return
        }

        self.selectedListTabID = tabs.first?.id
    }


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

        self.sourceSelectionStore.$preparingSource
            .receive(on: DispatchQueue.main)
            .assign(to: &self.$preparingSource)

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
        self.selectedSourceID = selectedSourceID
        self.selectedListTabID = nil
        self.errorMessage = nil
        self.items = []
        self.ensureSelectedListTab()
        self.saveCurrentLibraryState(lastRefreshAt: nil)

        do {
            // 中文注释：优先展示 Sources 入口刚请求到的当前结果；没有当前快照时保持空态，不从持久化缓存补数据。
            if self.applyPreparedSnapshotIfAvailable() == false {
                self.items = []
                self.logLibraryItems(
                    origin: "empty-after-source-switch-no-snapshot",
                    sourceID: selectedSourceID,
                    context: self.selectedListContext
                )
            }
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.loadFavoriteItemIDs()
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "switch-source-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    private func applyPreparedLibrarySnapshot(_ snapshot: SourceLibrarySnapshot?) {
        self.preparedLibrarySnapshot = snapshot

        guard self.applyPreparedSnapshotIfAvailable() else {
            return
        }

        do {
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.loadFavoriteItemIDs()
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "snapshot-favorite-load-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    private func applyPreparedSnapshotIfAvailable() -> Bool {
        guard let snapshot: SourceLibrarySnapshot = self.preparedLibrarySnapshot,
              snapshot.sourceID == self.selectedSourceID else {
            return false
        }

        self.items = snapshot.items
        self.logLibraryItems(
            origin: "current-snapshot",
            sourceID: snapshot.sourceID,
            context: self.selectedListContext
        )
        return true
    }

    private func loadCachedItemsForSelectedTab() {
        if self.applyPreparedSnapshotIfAvailable() == false {
            self.items = []
            self.logLibraryItems(
                origin: "empty-tab-switch-no-snapshot",
                sourceID: self.selectedSourceID,
                context: self.selectedListContext
            )
        }
    }

    private func loadCachedItems(context: ListContext?) {
        self.items = []
        self.logLibraryItems(
            origin: "disabled-cache-load",
            sourceID: self.selectedSourceID,
            context: context
        )
    }

    private var selectedListContext: ListContext? {
        return self.resolveLibrarySourcePresentationUseCase.listContext(from: self.selectedListTab)
    }

    private func restoreStartupLibraryState() throws {
        let persistedState: UserLibraryState? = try self.loadUserLibraryStateUseCase.execute(userID: self.userID)
        let persistedSource: Source? = persistedState.flatMap { state in
            return self.source(for: state.selectedSourceID)
        }
        let resolvedSource: Source? = persistedSource ?? self.sources.first

        guard let source: Source = resolvedSource else {
            self.selectedSourceID = nil
            self.sourceSelectionStore.selectedSourceID = nil
            self.selectedListTabID = nil
            self.items = []
            return
        }

        self.selectedSourceID = source.id
        self.sourceSelectionStore.selectedSourceID = source.id

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

        if self.selectedListContext != context {
            self.saveCurrentLibraryState(lastRefreshAt: nil)
        }
    }

    private func saveCurrentLibraryState(lastRefreshAt: Date?) {
        guard let selectedSourceID: String = self.selectedSourceID else {
            return
        }

        let state: UserLibraryState = UserLibraryState(
            userID: self.userID,
            selectedSourceID: selectedSourceID,
            listContext: self.selectedListContext,
            lastRefreshAt: lastRefreshAt,
            updatedAt: self.now()
        )

        do {
            try self.saveUserLibraryStateUseCase.execute(state: state)
        } catch {
            #if DEBUG
            print(
                "[BrowseCraftUserLibraryState] save failed " +
                "sourceID=\(selectedSourceID) " +
                "error=\(error)"
            )
            #endif
        }
    }

    private func contentItems(
        from output: SourceListOutput,
        source: Source,
        context: ListContext?
    ) -> [ContentItem] {
        return output.items.enumerated().map { index, item in
            return ContentItem(
                id: item.id,
                sourceId: source.id,
                title: item.title,
                detailURL: item.detailURL?.absoluteString ?? item.id,
                coverURL: item.coverURL?.absoluteString,
                type: self.contentType(for: source),
                latestText: item.latestText,
                updatedAt: item.updatedAt,
                listOrder: index,
                listContext: context
            )
        }
    }

    private func contentType(for source: Source) -> SourceContentKind {
        switch source.configuration {
        case .rss:
            return .article
        case .comic:
            return .comic
        case .plugin:
            return .article
        }
    }

    private func logLibraryItems(
        origin: String,
        sourceID: String?,
        context: ListContext?
    ) {
        #if DEBUG
        print(
            "[BrowseCraftLibraryData] origin=\(origin) " +
            "source=\(sourceID ?? "nil") " +
            "items=\(self.items.count) " +
            "firstItem=\(self.items.first?.id ?? "nil") " +
            "context=\(self.contextDescription(context))"
        )
        #endif
    }
}
