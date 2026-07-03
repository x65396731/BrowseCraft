import Foundation

// 中文注释：LoadHistoryUseCase.swift 属于应用用例层，用于说明本文件承载的核心职责。

/// 中文注释：为 History 功能加载历史记录和收藏 ID。
struct LoadHistoryUseCase {
    private let historyRepository: HistoryRepository
    private let favoriteRepository: FavoriteRepository

    init(historyRepository: HistoryRepository, favoriteRepository: FavoriteRepository) {
        self.historyRepository = historyRepository
        self.favoriteRepository = favoriteRepository
    }

    /// 中文注释：loadReadingHistory 方法封装当前类型的一段业务或界面行为。
    func loadReadingHistory() throws -> [ReadingHistory] {
        return try self.historyRepository.fetchReadingHistory()
    }

    /// 中文注释：loadFavoriteItemIDs 方法封装当前类型的一段业务或界面行为。
    func loadFavoriteItemIDs() throws -> Set<String> {
        return try self.favoriteRepository.fetchFavoriteItemIDs()
    }
}

