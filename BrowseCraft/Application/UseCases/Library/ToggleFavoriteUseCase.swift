import Foundation

// 中文注释：ToggleFavoriteUseCase.swift 属于应用用例层，用于说明本文件承载的核心职责。

/// 中文注释：读取并切换单个内容条目的收藏状态。
struct ToggleFavoriteUseCase {
    private let favoriteRepository: FavoriteRepository

    init(favoriteRepository: FavoriteRepository) {
        self.favoriteRepository = favoriteRepository
    }

    /// 中文注释：loadFavoriteItemIDs 方法封装当前类型的一段业务或界面行为。
    func loadFavoriteItemIDs() throws -> Set<String> {
        return try self.favoriteRepository.fetchFavoriteItemIDs()
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute(itemId: String) throws -> Set<String> {
        let currentIDs: Set<String> = try self.favoriteRepository.fetchFavoriteItemIDs()
        let shouldBecomeFavorite: Bool = !currentIDs.contains(itemId)

        try self.favoriteRepository.setFavorite(itemId: itemId, isFavorite: shouldBecomeFavorite)
        return try self.favoriteRepository.fetchFavoriteItemIDs()
    }
}

