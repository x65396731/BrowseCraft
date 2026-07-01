import Combine
import Foundation

// 中文注释：LibraryViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：LibraryViewModel 是 final class，负责本模块中的对应职责。
final class LibraryViewModel: ObservableObject {
    @Published private(set) var items: [ContentItem] = []
    @Published private(set) var sources: [Source] = []
    @Published private(set) var favoriteItemIDs: Set<String> = []
    @Published var errorMessage: String?

    private let loadLibraryUseCase: LoadLibraryUseCase
    private let loadSourcesUseCase: LoadSourcesUseCase
    private let toggleFavoriteUseCase: ToggleFavoriteUseCase
    private let recordOpenItemUseCase: RecordOpenItemUseCase

    init(
        loadLibraryUseCase: LoadLibraryUseCase,
        loadSourcesUseCase: LoadSourcesUseCase,
        toggleFavoriteUseCase: ToggleFavoriteUseCase,
        recordOpenItemUseCase: RecordOpenItemUseCase
    ) {
        self.loadLibraryUseCase = loadLibraryUseCase
        self.loadSourcesUseCase = loadSourcesUseCase
        self.toggleFavoriteUseCase = toggleFavoriteUseCase
        self.recordOpenItemUseCase = recordOpenItemUseCase
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() {
        do {
            self.items = try self.loadLibraryUseCase.execute()
            self.sources = try self.loadSourcesUseCase.execute()
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.loadFavoriteItemIDs()
        } catch {
            self.errorMessage = error.localizedDescription
        }
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
}
