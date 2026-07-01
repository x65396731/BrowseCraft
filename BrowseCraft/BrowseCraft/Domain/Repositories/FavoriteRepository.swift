import Foundation

/// Domain-facing storage API for favorites.
protocol FavoriteRepository {
    func fetchFavoriteItemIDs() throws -> Set<String>
    func setFavorite(itemId: String, isFavorite: Bool) throws
}

