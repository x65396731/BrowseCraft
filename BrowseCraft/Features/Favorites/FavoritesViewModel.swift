import Observation
import BrowseCraftDomain
import Foundation

// 中文注释：FavoritesViewModel 负责收藏页数据加载与详情入口。

@MainActor
@Observable
final class FavoritesViewModel {
    private(set) var favoriteItems: [FavoriteContentItem] = []
    private(set) var sources: [Source] = []
    var errorMessage: String?

    private let persistenceCoordinator: FavoritesPersistenceCoordinator

    init(
        persistenceCoordinator: FavoritesPersistenceCoordinator,
        userID _: String = AppUser.localDefaultID
    ) {
        self.persistenceCoordinator = persistenceCoordinator
    }

    @MainActor
    func load() async {
        do {
            let snapshot: FavoritesPersistenceSnapshot = try await self.persistenceCoordinator.load()
            self.sources = snapshot.sources
            self.favoriteItems = snapshot.items
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
