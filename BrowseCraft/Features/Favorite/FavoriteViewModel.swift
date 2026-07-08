import Combine
import Foundation

// 中文注释：FavoriteViewModel 负责收藏页数据加载与详情入口。

final class FavoriteViewModel: ObservableObject {
    @Published private(set) var favoriteItems: [FavoriteContentItem] = []
    @Published private(set) var sources: [Source] = []
    @Published var errorMessage: String?

    private let loadFavoriteItemsUseCase: ToggleFavoriteUseCase
    private let loadSourcesUseCase: LoadSourcesUseCase

    init(
        loadFavoriteItemsUseCase: ToggleFavoriteUseCase,
        loadSourcesUseCase: LoadSourcesUseCase,
        userID _: String = AppUser.localDefaultID
    ) {
        self.loadFavoriteItemsUseCase = loadFavoriteItemsUseCase
        self.loadSourcesUseCase = loadSourcesUseCase
    }

    @MainActor
    func load() {
        do {
            self.sources = try self.loadSourcesUseCase.execute()
            self.favoriteItems = try self.loadFavoriteItemsUseCase.loadFavoriteItems()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func source(for item: FavoriteContentItem) -> Source? {
        if let currentSource: Source = self.sources.first(where: { source in
            source.id == item.sourceID
        }) {
            return currentSource
        }

        return item.fallbackSource()
    }

    func sourceName(for item: FavoriteContentItem) -> String {
        return self.source(for: item)?.name ?? item.sourceSnapshot?.name ?? "Unknown Source"
    }
}
