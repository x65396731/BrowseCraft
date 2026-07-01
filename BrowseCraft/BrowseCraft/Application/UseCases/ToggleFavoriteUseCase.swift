import Foundation

/// Reads and writes favorite state for one content item.
struct ToggleFavoriteUseCase {
    private let favoriteRepository: FavoriteRepository

    init(favoriteRepository: FavoriteRepository) {
        self.favoriteRepository = favoriteRepository
    }

    func loadFavoriteItemIDs() throws -> Set<String> {
        return try self.favoriteRepository.fetchFavoriteItemIDs()
    }

    func execute(itemId: String) throws -> Set<String> {
        let currentIDs: Set<String> = try self.favoriteRepository.fetchFavoriteItemIDs()
        let shouldBecomeFavorite: Bool = !currentIDs.contains(itemId)

        try self.favoriteRepository.setFavorite(itemId: itemId, isFavorite: shouldBecomeFavorite)
        return try self.favoriteRepository.fetchFavoriteItemIDs()
    }
}

