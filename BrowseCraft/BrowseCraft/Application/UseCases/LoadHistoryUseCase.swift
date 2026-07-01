import Foundation

/// Loads history and favorite IDs for the History feature.
struct LoadHistoryUseCase {
    private let historyRepository: HistoryRepository
    private let favoriteRepository: FavoriteRepository

    init(historyRepository: HistoryRepository, favoriteRepository: FavoriteRepository) {
        self.historyRepository = historyRepository
        self.favoriteRepository = favoriteRepository
    }

    func loadReadingHistory() throws -> [ReadingHistory] {
        return try self.historyRepository.fetchReadingHistory()
    }

    func loadFavoriteItemIDs() throws -> Set<String> {
        return try self.favoriteRepository.fetchFavoriteItemIDs()
    }
}

