import Combine
import Foundation

// 中文注释：LibraryViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

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
    private let refreshSourceUseCase: RefreshSourceUseCase
    private let sourceSelectionStore: SourceSelectionStore
    private var cancellables: Set<AnyCancellable> = Set<AnyCancellable>()

    init(
        loadLibraryUseCase: LoadLibraryUseCase,
        loadSourcesUseCase: LoadSourcesUseCase,
        toggleFavoriteUseCase: ToggleFavoriteUseCase,
        recordOpenItemUseCase: RecordOpenItemUseCase,
        refreshSourceUseCase: RefreshSourceUseCase,
        sourceSelectionStore: SourceSelectionStore
    ) {
        self.loadLibraryUseCase = loadLibraryUseCase
        self.loadSourcesUseCase = loadSourcesUseCase
        self.toggleFavoriteUseCase = toggleFavoriteUseCase
        self.recordOpenItemUseCase = recordOpenItemUseCase
        self.refreshSourceUseCase = refreshSourceUseCase
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

            self.items = try self.loadLibraryUseCase.execute(sourceId: self.selectedSourceID)
            self.ensureSelectedListTab()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func selectListTab(_ tab: ListTabRule) async {
        if self.selectedListTabID != tab.id {
            self.selectedListTabID = tab.id
            self.items = []
        }

        await self.refreshSelectedListTab()
    }

    @MainActor
    func refreshSelectedListTab() async {
        guard let selectedSource: Source = self.selectedSource else {
            return
        }

        self.ensureSelectedListTab()
        self.isRefreshing = true

        do {
            let refreshedItems: [ContentItem] = try await self.refreshSourceUseCase.execute(
                source: selectedSource,
                listTab: self.selectedListTab
            )
            self.items = refreshedItems
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.loadFavoriteItemIDs()
        } catch {
            self.errorMessage = error.localizedDescription
        }

        self.isRefreshing = false
    }

    @MainActor
    /// 中文注释：toggleFavorite 方法封装当前类型的一段业务或界面行为。
    func toggleFavorite(item: ContentItem) {
        do {
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.execute(itemId: item.id)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    /// 中文注释：recordOpened 方法封装当前类型的一段业务或界面行为。
    func recordOpened(item: ContentItem) {
        do {
            try self.recordOpenItemUseCase.execute(itemId: item.id)
        } catch {
            self.errorMessage = error.localizedDescription
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

    var listTabs: [ListTabRule] {
        return self.selectedSource?.rule.availableListTabs ?? []
    }

    var selectedListTab: ListTabRule? {
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

        self.selectedSourceID = selectedSourceID
        self.selectedListTabID = nil

        do {
            self.items = try self.loadLibraryUseCase.execute(sourceId: selectedSourceID)
            self.ensureSelectedListTab()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
