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

    private let syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase
    private let loadSourcesUseCase: LoadSourcesUseCase
    private let toggleFavoriteUseCase: ToggleFavoriteUseCase
    private let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase
    private let videoTabDiscoveryUseCase: VideoSourceTabDiscoveryUseCase?
    private let loadUserLibraryStateUseCase: LoadUserLibraryStateUseCase
    private let saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase
    private let resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase
    private let sourceSelectionStore: SourceSelectionStore
    private let userID: String
    private let now: () -> Date
    private var cancellables: Set<AnyCancellable> = Set<AnyCancellable>()
    private var tabDiscoveryAttemptedSourceIDs: Set<String> = Set<String>()
    private var confirmedEmptyListTabKeys: Set<String> = Set<String>()
    /// 中文注释：刷新令牌用于避免旧 source 的慢请求回写或提前关闭当前 source 的 loading。
    private var refreshToken: Int = 0

    init(
        syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase,
        loadSourcesUseCase: LoadSourcesUseCase,
        toggleFavoriteUseCase: ToggleFavoriteUseCase,
        refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase,
        videoTabDiscoveryUseCase: VideoSourceTabDiscoveryUseCase? = nil,
        loadUserLibraryStateUseCase: LoadUserLibraryStateUseCase,
        saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase,
        resolveLibrarySourcePresentationUseCase: ResolveLibrarySourcePresentationUseCase,
        sourceSelectionStore: SourceSelectionStore,
        userID: String = AppUser.localDefaultID,
        now: @escaping () -> Date = Date.init
    ) {
        self.syncBuiltInSourcesUseCase = syncBuiltInSourcesUseCase
        self.loadSourcesUseCase = loadSourcesUseCase
        self.toggleFavoriteUseCase = toggleFavoriteUseCase
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
        self.videoTabDiscoveryUseCase = videoTabDiscoveryUseCase
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
            try self.syncBuiltInSourcesUseCase.execute()
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

        guard self.visibleListTabs.contains(where: { tab in tab.id == tabID }) else {
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
        guard self.selectedSource != nil else {
            return
        }

        await self.discoverTabsForSelectedVideoSourceIfNeeded()
        CrashDiagnostics.shared.setRuleStage(.list)
        self.ensureSelectedListTab()
        guard let refreshedSelectedSource: Source = self.selectedSource else {
            return
        }

        let expectedSourceID: String = refreshedSelectedSource.id
        let expectedTabID: String? = self.selectedListTab?.id
        let expectedListContext: ListContext? = self.selectedListContext
        self.refreshToken += 1
        let currentRefreshToken: Int = self.refreshToken
        var shouldRefreshReplacementTab: Bool = false
        self.isRefreshing = true

        do {
            let output: SourceListOutput = try await self.refreshSourceRuntimeUseCase.execute(
                source: refreshedSelectedSource,
                listContext: expectedListContext
            )
            if Task.isCancelled == false,
               self.refreshToken == currentRefreshToken,
               self.selectedSourceID == expectedSourceID,
               self.selectedListTab?.id == expectedTabID {
                let refreshedItems: [ContentItem] = self.contentItems(
                    from: output,
                    source: refreshedSelectedSource,
                    context: expectedListContext
                )
                self.items = refreshedItems
                if self.updateConfirmedEmptyListTab(
                    sourceID: expectedSourceID,
                    tabID: expectedTabID,
                    itemCount: refreshedItems.count
                ) {
                    self.ensureSelectedListTab()
                    shouldRefreshReplacementTab = self.selectedListTabID != expectedTabID
                }
                self.sourceSelectionStore.publishLibrarySnapshot(
                    source: refreshedSelectedSource,
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
                AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .list, errorCode: "library-refresh-error")
                self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            }
        }

        if self.refreshToken == currentRefreshToken {
            self.isRefreshing = false
        }

        if shouldRefreshReplacementTab,
           self.refreshToken == currentRefreshToken,
           self.selectedSourceID == expectedSourceID {
            await self.refreshSelectedListTab()
        }
    }

    @MainActor
    /// 中文注释：toggleFavorite 方法封装当前类型的一段业务或界面行为。
    func toggleFavorite(item: ContentItem) {
        do {
            let wasFavorite: Bool = self.favoriteItemIDs.contains(item.id)
            let source: Source? = self.source(for: item.sourceId)
            let favoriteItem: FavoriteContentItem = FavoriteContentItem(
                id: item.id,
                sourceID: item.sourceId,
                title: item.title,
                detailURL: item.detailURL,
                coverURL: item.coverURL,
                kind: self.favoriteKind(for: item),
                latestText: item.latestText,
                updatedAt: item.updatedAt,
                favoritedAt: self.now(),
                listOrder: item.listOrder,
                listContext: item.listContext,
                sourceSnapshot: source.map(FavoriteSourceSnapshot.init(source:))
            )
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.execute(item: favoriteItem)
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
        guard self.selectedSource?.configuration.kind == .video,
              let sourceID: String = self.selectedSourceID else {
            return tabs
        }

        let visibleTabs: [ListTabRule] = tabs.filter { tab in
            return self.confirmedEmptyListTabKeys.contains(self.listTabKey(sourceID: sourceID, tabID: tab.id)) == false
        }

        return visibleTabs.isEmpty ? tabs : visibleTabs
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
    }

    private func updateConfirmedEmptyListTab(
        sourceID: String,
        tabID: String?,
        itemCount: Int
    ) -> Bool {
        guard let tabID: String else {
            return false
        }

        let key: String = self.listTabKey(sourceID: sourceID, tabID: tabID)
        let wasHidden: Bool = self.confirmedEmptyListTabKeys.contains(key)
        if itemCount == 0 {
            self.confirmedEmptyListTabKeys.insert(key)
        } else {
            self.confirmedEmptyListTabKeys.remove(key)
        }

        return wasHidden != self.confirmedEmptyListTabKeys.contains(key)
    }

    private func listTabKey(sourceID: String, tabID: String) -> String {
        return "\(sourceID)::\(tabID)"
    }

    @MainActor
    private func discoverTabsForSelectedVideoSourceIfNeeded() async {
        guard let videoTabDiscoveryUseCase: VideoSourceTabDiscoveryUseCase,
              let source: Source = self.selectedSource,
              case .video(let configuration) = source.configuration,
              configuration.listTabs.count <= 1,
              self.tabDiscoveryAttemptedSourceIDs.contains(source.id) == false else {
            return
        }

        self.tabDiscoveryAttemptedSourceIDs.insert(source.id)
        CrashDiagnostics.shared.setRuleStage(.list)

        do {
            let tabs: [VideoSourceListTab] = try await videoTabDiscoveryUseCase.discoverTabs(
                sourceID: source.id,
                definition: configuration.definition,
                explicitTabs: configuration.listTabs
            )
            guard tabs != configuration.listTabs else {
                return
            }

            var updatedSource: Source = source
            updatedSource.configuration = .video(
                VideoSourceConfiguration(
                    definition: configuration.definition,
                    listTabs: tabs
                )
            )
            self.upsertSource(updatedSource)
            self.ensureSelectedListTab()
            #if DEBUG
            print(
                "[BrowseCraftLibraryTabs] origin=webview-discovery " +
                "source=\(source.id) " +
                "count=\(tabs.count)"
            )
            #endif
        } catch {
            RuleExecutionErrorClassifier.log(
                error: error,
                stage: .list,
                event: "library-tab-discovery-error"
            )
        }
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

        print(
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
        CrashDiagnostics.shared.setSource(selectedSourceID.flatMap { self.source(for: $0) })
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
            AppAnalytics.shared.logDiagnosticFailure(error: error, stage: .list, errorCode: "switch-source-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
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

        self.upsertSource(snapshot.source)
        self.items = snapshot.items
        self.logLibraryItems(
            origin: "current-snapshot",
            sourceID: snapshot.sourceID,
            context: self.selectedListContext
        )
        return true
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
            guard let selectedSourceID: String = state.selectedSourceID else {
                return nil
            }

            return self.source(for: selectedSourceID)
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
        case .video:
            return .video
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

    private func favoriteKind(for item: ContentItem) -> FavoriteContentKind {
        switch item.type {
        case .article:
            return .rss
        case .comic:
            return .comic
        case .video:
            return self.source(for: item.sourceId)?.favoriteVideoKind ?? .videoNative
        default:
            return .rss
        }
    }
}
