import BrowseCraftDomain
import Foundation

struct FavoritesPersistenceSnapshot: Sendable {
    let items: [FavoriteContentItem]
    let sources: [Source]
}

actor FavoritesPersistenceCoordinator {
    private let loadFavoriteItemsUseCase: ToggleFavoriteUseCase
    private let reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase

    init(
        loadFavoriteItemsUseCase: ToggleFavoriteUseCase,
        reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase
    ) {
        self.loadFavoriteItemsUseCase = loadFavoriteItemsUseCase
        self.reconcileSourceSlotAssignmentsUseCase = reconcileSourceSlotAssignmentsUseCase
    }

    func remove(item: FavoriteContentItem) throws -> FavoritesPersistenceSnapshot {
        try self.loadFavoriteItemsUseCase.removeFavorite(item)
        return try self.load()
    }

    /// 批量取消收藏（选择模式）：逐条取消，最后读一次。
    func remove(items: [FavoriteContentItem]) throws -> FavoritesPersistenceSnapshot {
        for item: FavoriteContentItem in items {
            try self.loadFavoriteItemsUseCase.removeFavorite(item)
        }
        return try self.load()
    }

    func load() throws -> FavoritesPersistenceSnapshot {
        return FavoritesPersistenceSnapshot(
            items: try self.loadFavoriteItemsUseCase.loadFavoriteItems(),
            sources: try self.reconcileSourceSlotAssignmentsUseCase.execute()
        )
    }
}
