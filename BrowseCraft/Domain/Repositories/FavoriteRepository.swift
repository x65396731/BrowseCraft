import Foundation

// 中文注释：FavoriteRepository.swift 属于仓储协议层，用于说明本文件承载的核心职责。

/// 中文注释：面向领域层的收藏仓储协议，负责收藏状态的读取和切换。
protocol FavoriteRepository {
    /// 中文注释：fetchFavoriteItemIDs 方法封装当前类型的一段业务或界面行为。
    func fetchFavoriteItemIDs() throws -> Set<String>
    /// 中文注释：setFavorite 方法封装当前类型的一段业务或界面行为。
    func setFavorite(itemId: String, isFavorite: Bool) throws
}

