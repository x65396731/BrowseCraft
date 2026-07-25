import Combine
import Foundation

// 中文注释：FavoritesViewModel 负责收藏页数据加载与详情入口。

final class FavoritesViewModel: ObservableObject {
    @Published private(set) var favoriteItems: [FavoriteContentItem] = []
    @Published private(set) var sources: [Source] = []
    @Published var errorMessage: String?

    private let loadFavoriteItemsUseCase: ToggleFavoriteUseCase
    private let reconcileSourceSlotAssignmentsUseCase:
        ReconcileSourceSlotAssignmentsUseCase

    init(
        loadFavoriteItemsUseCase: ToggleFavoriteUseCase,
        reconcileSourceSlotAssignmentsUseCase:
            ReconcileSourceSlotAssignmentsUseCase,
        userID _: String = AppUser.localDefaultID
    ) {
        self.loadFavoriteItemsUseCase = loadFavoriteItemsUseCase
        self.reconcileSourceSlotAssignmentsUseCase =
            reconcileSourceSlotAssignmentsUseCase
    }

    @MainActor
    func load() {
        do {
            self.sources = try self.reconcileSourceSlotAssignmentsUseCase.execute()
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
