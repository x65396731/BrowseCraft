import Combine
import Foundation

// 中文注释：SourcesViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：Sources 标签页的视图模型，管理源列表、选中源、刷新状态和错误信息。
/// 中文注释：SwiftUI 会观察这里的 @Published 属性，并在变化时刷新对应界面。
final class SourcesViewModel: ObservableObject {
    @Published private(set) var sources: [Source] = []
    @Published var selectedSourceID: String?
    @Published var errorMessage: String?
    @Published private(set) var isRefreshing: Bool = false

    private let loadBuiltInSourcesUseCase: LoadBuiltInSourcesUseCase
    private let loadSourcesUseCase: LoadSourcesUseCase
    private let addSourceUseCase: AddSourceUseCase
    private let deleteSourceUseCase: DeleteSourceUseCase
    private let refreshSourceUseCase: RefreshSourceUseCase

    init(
        loadBuiltInSourcesUseCase: LoadBuiltInSourcesUseCase,
        loadSourcesUseCase: LoadSourcesUseCase,
        addSourceUseCase: AddSourceUseCase,
        deleteSourceUseCase: DeleteSourceUseCase,
        refreshSourceUseCase: RefreshSourceUseCase
    ) {
        self.loadBuiltInSourcesUseCase = loadBuiltInSourcesUseCase
        self.loadSourcesUseCase = loadSourcesUseCase
        self.addSourceUseCase = addSourceUseCase
        self.deleteSourceUseCase = deleteSourceUseCase
        self.refreshSourceUseCase = refreshSourceUseCase
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() {
        do {
            try self.loadBuiltInSourcesUseCase.execute()
            let loadedSources: [Source] = try self.loadSourcesUseCase.execute()
            self.sources = loadedSources

            if self.selectedSourceID == nil {
                self.selectedSourceID = loadedSources.first?.id
            }
        } catch {
            self.errorMessage = error.localizedDescription
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
            self.selectedSourceID = source.id
            return true
        } catch {
            self.errorMessage = error.localizedDescription
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
                self.selectedSourceID = loadedSources.first?.id
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    /// 中文注释：refreshSelectedSource 方法封装当前类型的一段业务或界面行为。
    func refreshSelectedSource() async {
        guard let selectedSource: Source = self.selectedSource else {
            return
        }

        self.isRefreshing = true

        do {
            _ = try await self.refreshSourceUseCase.execute(source: selectedSource)
        } catch {
            self.errorMessage = error.localizedDescription
        }

        self.isRefreshing = false
    }

    var selectedSource: Source? {
        return self.sources.first { source in
            return source.id == self.selectedSourceID
        }
    }
}
