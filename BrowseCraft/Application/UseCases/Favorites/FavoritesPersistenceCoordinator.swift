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

    func load() throws -> FavoritesPersistenceSnapshot {
        return FavoritesPersistenceSnapshot(
            items: try self.loadFavoriteItemsUseCase.loadFavoriteItems(),
            sources: try self.reconcileSourceSlotAssignmentsUseCase.execute()
        )
    }
}
