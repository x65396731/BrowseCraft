import Combine
import Foundation

// 中文注释：SourcesViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：Sources 标签页的视图模型，管理源列表、选中源、刷新状态和错误信息。
/// 中文注释：SwiftUI 会观察这里的 @Published 属性，并在变化时刷新对应界面。
final class SourcesViewModel: ObservableObject {
    private enum FailedRefreshAction {
        case select(sourceID: String)
        case refresh(sourceID: String)
    }

    @Published private(set) var sources: [Source] = []
    @Published private(set) var selectedSourceID: String?
    @Published var errorMessage: String?
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var refreshingSourceID: String?

    private let loadBuiltInSourcesUseCase: LoadBuiltInSourcesUseCase
    private let loadSourcesUseCase: LoadSourcesUseCase
    private let addSourceUseCase: AddSourceUseCase
    private let deleteSourceUseCase: DeleteSourceUseCase
    private let refreshSourceUseCase: RefreshSourceUseCase
    private let sourceSelectionStore: SourceSelectionStore
    private var cancellables: Set<AnyCancellable> = Set<AnyCancellable>()
    private var failedRefreshAction: FailedRefreshAction?

    init(
        loadBuiltInSourcesUseCase: LoadBuiltInSourcesUseCase,
        loadSourcesUseCase: LoadSourcesUseCase,
        addSourceUseCase: AddSourceUseCase,
        deleteSourceUseCase: DeleteSourceUseCase,
        refreshSourceUseCase: RefreshSourceUseCase,
        sourceSelectionStore: SourceSelectionStore
    ) {
        self.loadBuiltInSourcesUseCase = loadBuiltInSourcesUseCase
        self.loadSourcesUseCase = loadSourcesUseCase
        self.addSourceUseCase = addSourceUseCase
        self.deleteSourceUseCase = deleteSourceUseCase
        self.refreshSourceUseCase = refreshSourceUseCase
        self.sourceSelectionStore = sourceSelectionStore
        self.selectedSourceID = sourceSelectionStore.selectedSourceID
        self.bindSourceSelection()
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() {
        do {
            try self.loadBuiltInSourcesUseCase.execute()
            let loadedSources: [Source] = try self.loadSourcesUseCase.execute()
            self.sources = loadedSources

            if self.selectedSourceID == nil {
                self.selectSource(id: loadedSources.first?.id)
            }
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-load-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    @MainActor
    /// 中文注释：addSource 方法封装当前类型的一段业务或界面行为。
    func addSource(name: String, baseURL: String, ruleJSON: String) -> Bool {
        do {
            let source: Source = try self.addSourceUseCase.execute(
                name: name,
                baseURL: baseURL,
                ruleJSON: ruleJSON
            )

            self.load()
            self.selectSource(id: source.id)
            return true
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-add-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
            return false
        }
    }

    @MainActor
    /// 中文注释：deleteSources 方法封装当前类型的一段业务或界面行为。
    func deleteSources(at offsets: IndexSet) {
        do {
            let sourceIDs: [String] = offsets.map { offset in
                return self.sources[offset].id
            }

            for sourceID: String in sourceIDs {
                try self.deleteSourceUseCase.execute(sourceId: sourceID)
            }

            let loadedSources: [Source] = try self.loadSourcesUseCase.execute()
            self.sources = loadedSources

            if let selectedSourceID: String = self.selectedSourceID,
               loadedSources.contains(where: { source in source.id == selectedSourceID }) == false {
                self.selectSource(id: loadedSources.first?.id)
            }
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-delete-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }
    }

    func selectSource(id: String?) {
        self.selectedSourceID = id
        self.sourceSelectionStore.selectedSourceID = id
    }

    @MainActor
    func selectSourceAfterRefresh(_ source: Source) async {
        if self.selectedSourceID == source.id || self.isRefreshing {
            return
        }

        self.isRefreshing = true
        self.refreshingSourceID = source.id

        do {
            _ = try await self.refreshSourceUseCase.execute(source: source)
            self.failedRefreshAction = nil
            self.selectSource(id: source.id)
        } catch {
            self.failedRefreshAction = .select(sourceID: source.id)
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-select-refresh-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }

        self.refreshingSourceID = nil
        self.isRefreshing = false
    }

    @MainActor
    /// 中文注释：refreshSelectedSource 方法封装当前类型的一段业务或界面行为。
    func refreshSelectedSource() async {
        guard let selectedSource: Source = self.selectedSource else {
            return
        }

        await self.refreshSource(selectedSource)
    }

    @MainActor
    func retryFailedRefresh() async {
        let failedRefreshAction: FailedRefreshAction? = self.failedRefreshAction
        self.errorMessage = nil

        guard let failedRefreshAction: FailedRefreshAction = failedRefreshAction else {
            return
        }

        switch failedRefreshAction {
        case .select(let sourceID):
            guard let source: Source = self.source(id: sourceID) else {
                return
            }

            await self.selectSourceAfterRefresh(source)
        case .refresh(let sourceID):
            guard let source: Source = self.source(id: sourceID) else {
                return
            }

            await self.refreshSource(source)
        }
    }

    func clearError() {
        self.errorMessage = nil
    }

    var selectedSource: Source? {
        return self.source(id: self.selectedSourceID)
    }

    private func source(id: String?) -> Source? {
        guard let id: String = id else {
            return nil
        }

        return self.sources.first { source in
            return source.id == id
        }
    }

    @MainActor
    private func refreshSource(_ source: Source) async {
        if self.isRefreshing {
            return
        }

        self.isRefreshing = true
        self.refreshingSourceID = source.id

        do {
            _ = try await self.refreshSourceUseCase.execute(source: source)
            self.failedRefreshAction = nil
        } catch {
            self.failedRefreshAction = .refresh(sourceID: source.id)
            RuleExecutionErrorClassifier.log(error: error, stage: .list, event: "source-refresh-error")
            self.errorMessage = RuleExecutionErrorClassifier.userMessage(for: error)
        }

        self.refreshingSourceID = nil
        self.isRefreshing = false
    }

    private func bindSourceSelection() {
        self.sourceSelectionStore.$selectedSourceID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedSourceID in
                self?.selectedSourceID = selectedSourceID
            }
            .store(in: &self.cancellables)
    }
}
