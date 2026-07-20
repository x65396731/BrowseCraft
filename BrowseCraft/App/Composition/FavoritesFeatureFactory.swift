struct FavoritesFeatureFactory {
    private let sourceRepository: SourceRepository
    private let favoriteRepository: FavoriteRepository

    init(sourceRepository: SourceRepository, favoriteRepository: FavoriteRepository) {
        self.sourceRepository = sourceRepository
        self.favoriteRepository = favoriteRepository
    }

    func makeViewModel() -> FavoritesViewModel {
        return FavoritesViewModel(
            loadFavoriteItemsUseCase: ToggleFavoriteUseCase(
                favoriteRepository: self.favoriteRepository
            ),
            loadSourcesUseCase: LoadSourcesUseCase(
                sourceRepository: self.sourceRepository
            )
        )
    }
}
