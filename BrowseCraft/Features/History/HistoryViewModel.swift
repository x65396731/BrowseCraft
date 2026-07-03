import Combine
import Foundation

// 中文注释：HistoryViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：HistoryViewModel 是 final class，负责本模块中的对应职责。
final class HistoryViewModel: ObservableObject {
    @Published private(set) var readingHistory: [ReadingHistory] = []
    @Published private(set) var items: [ContentItem] = []
    @Published private(set) var sources: [Source] = []
    @Published private(set) var favoriteItemIDs: Set<String> = []
    @Published var errorMessage: String?

    private let loadHistoryUseCase: LoadHistoryUseCase
    private let loadLibraryUseCase: LoadLibraryUseCase
    private let loadSourcesUseCase: LoadSourcesUseCase

    init(
        loadHistoryUseCase: LoadHistoryUseCase,
        loadLibraryUseCase: LoadLibraryUseCase,
        loadSourcesUseCase: LoadSourcesUseCase
    ) {
        self.loadHistoryUseCase = loadHistoryUseCase
        self.loadLibraryUseCase = loadLibraryUseCase
        self.loadSourcesUseCase = loadSourcesUseCase
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() {
        do {
            self.readingHistory = try self.loadHistoryUseCase.loadReadingHistory()
            self.favoriteItemIDs = try self.loadHistoryUseCase.loadFavoriteItemIDs()
            self.items = try self.loadLibraryUseCase.execute()
            self.sources = try self.loadSourcesUseCase.execute()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    var favoriteItems: [ContentItem] {
        return self.items.filter { item in
            return self.favoriteItemIDs.contains(item.id)
        }
    }

    /// 中文注释：item 方法封装当前类型的一段业务或界面行为。
    func item(for history: ReadingHistory) -> ContentItem? {
        return self.items.first { item in
            return item.id == history.itemId
        }
    }

    /// 中文注释：sourceName 方法封装当前类型的一段业务或界面行为。
    func sourceName(for sourceId: String) -> String {
        let source: Source? = self.sources.first { source in
            return source.id == sourceId
        }

        return source?.name ?? "Unknown Source"
    }
}
