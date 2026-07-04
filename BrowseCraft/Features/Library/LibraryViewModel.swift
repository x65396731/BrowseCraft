import Combine
import Foundation

// 中文注释：LibraryViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

struct LibraryListTabState: Identifiable, Hashable {
    let id: String
    let title: String
    let isSelected: Bool
}

/// 中文注释：LibraryViewModel 是 final class，负责本模块中的对应职责。
final class LibraryViewModel: ObservableObject {
    @Published private(set) var items: [ContentItem] = []
    @Published private(set) var sources: [Source] = []
    @Published private(set) var favoriteItemIDs: Set<String> = []
    @Published private(set) var selectedSourceID: String?
    @Published var selectedListTabID: String?
    @Published var errorMessage: String?
    @Published private(set) var isRefreshing: Bool = false

    private let loadLibraryUseCase: LoadLibraryUseCase
    private let loadSourcesUseCase: LoadSourcesUseCase
    private let toggleFavoriteUseCase: ToggleFavoriteUseCase
    private let recordOpenItemUseCase: RecordOpenItemUseCase
    private let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase
    private let sourceSelectionStore: SourceSelectionStore
    private var cancellables: Set<AnyCancellable> = Set<AnyCancellable>()
    /// 中文注释：刷新令牌用于避免旧 source 的慢请求回写或提前关闭当前 source 的 loading。
    private var refreshToken: Int = 0

    init(
        loadLibraryUseCase: LoadLibraryUseCase,
        loadSourcesUseCase: LoadSourcesUseCase,
        toggleFavoriteUseCase: ToggleFavoriteUseCase,
        recordOpenItemUseCase: RecordOpenItemUseCase,
        refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase,
        sourceSelectionStore: SourceSelectionStore
    ) {
        self.loadLibraryUseCase = loadLibraryUseCase
        self.loadSourcesUseCase = loadSourcesUseCase
        self.toggleFavoriteUseCase = toggleFavoriteUseCase
        self.recordOpenItemUseCase = recordOpenItemUseCase
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
        self.sourceSelectionStore = sourceSelectionStore
        self.selectedSourceID = sourceSelectionStore.selectedSourceID
        self.bindSourceSelection()
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() {
        do {
            self.sources = try self.loadSourcesUseCase.execute()
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.loadFavoriteItemIDs()

            if self.selectedSourceID == nil {
                let defaultSourceID: String? = self.sources.first?.id
                self.selectedSourceID = defaultSourceID
                self.sourceSelectionStore.selectedSourceID = defaultSourceID
            }

            self.ensureSelectedListTab()
            let selectedListContext: ListContext? = self.selectedListContext
            self.items = try self.loadLibraryUseCase.execute(
                sourceId: self.selectedSourceID,
                context: selectedListContext
            )
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
            _ = try await self.refreshSourceRuntimeUseCase.execute(
                source: selectedSource,
                listContext: expectedListContext
            )
            if Task.isCancelled == false,
               self.refreshToken == currentRefreshToken,
               self.selectedSourceID == expectedSourceID,
               self.selectedListTab?.id == expectedTabID {
                self.loadCachedItems(context: expectedListContext)
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

    @MainActor
    /// 中文注释：recordOpened 方法封装当前类型的一段业务或界面行为。
    func recordOpened(item: ContentItem) {
        do {
            try self.recordOpenItemUseCase.execute(itemId: item.id)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "record-open-error")
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
        return source.rule.request(for: self.selectedListTab)
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
        return RuleResolver().resolve(source.rule).treatsDetailURLAsChapter
    }

    private var listTabs: [ListTabRule] {
        return self.selectedSource?.rule.availableListTabs ?? []
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

    private func bindSourceSelection() {
        self.sourceSelectionStore.$selectedSourceID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedSourceID in
                self?.applySelectedSourceID(selectedSourceID)
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

        do {
            // 中文注释：Sources 页已经在遮盖状态下刷新并保存数据；Library 切换时只读取新 source 的已保存结果。
            let selectedListContext: ListContext? = self.selectedListContext
            self.items = try self.loadLibraryUseCase.execute(
                sourceId: selectedSourceID,
                context: selectedListContext
            )
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.loadFavoriteItemIDs()
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "switch-source-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    private func loadCachedItemsForSelectedTab() {
        self.loadCachedItems(context: self.selectedListContext)
    }

    private func loadCachedItems(context: ListContext?) {
        do {
            self.items = try self.loadLibraryUseCase.execute(
                sourceId: self.selectedSourceID,
                context: context
            )
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "tab-cache-load-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    private var selectedListContext: ListContext? {
        return self.listContext(from: self.selectedListTab)
    }

    private func listContext(from listTab: ListTabRule?) -> ListContext? {
        guard let listTab: ListTabRule = listTab else {
            return nil
        }

        if var context: ListContext = listTab.context {
            if context.listRuleId == nil {
                context.listRuleId = listTab.list.id
            }

            return context
        }

        return ListContext(
            pageId: listTab.id,
            tabId: listTab.id,
            sectionId: nil,
            listRuleId: listTab.list.id,
            sectionRole: .main
        )
    }
}
