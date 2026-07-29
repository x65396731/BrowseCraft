struct FavoritesFeatureFactory {
    private let sourceRepository: SourceRepository
    private let favoriteRepository: FavoriteRepository

    init(sourceRepository: SourceRepository, favoriteRepository: FavoriteRepository) {
        self.sourceRepository = sourceRepository
        self.favoriteRepository = favoriteRepository
    }

    @MainActor
    func makeViewModel() -> FavoritesViewModel {
        return FavoritesViewModel(
            persistenceCoordinator: FavoritesPersistenceCoordinator(
                loadFavoriteItemsUseCase: ToggleFavoriteUseCase(
                    favoriteRepository: self.favoriteRepository
                ),
                reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase(
                    sourceRepository: self.sourceRepository
                )
            )
        )
    }
}
