import Foundation

// 中文注释：FavoriteRepository.swift 属于仓储协议层，用于说明本文件承载的核心职责。

/// 中文注释：面向领域层的收藏仓储协议，负责收藏状态的读取和切换。
protocol FavoriteRepository: Sendable {
    /// 中文注释：当前用户已收藏条目的 id 集合；`sourceID` 为 nil 时跨全部来源。
    func fetchFavoriteItemIDs(sourceID: String?) throws -> Set<String>
    func fetchFavoriteItems() throws -> [FavoriteContentItem]
    /// 中文注释：写入或取消一条收藏。
    func setFavorite(item: FavoriteContentItem, isFavorite: Bool) throws
    /// 中文注释：撤销取消收藏——按条目自带的 `favoritedAt` 重新收藏，不改成当前时间，收藏页的日期分组才不跳动。
    func restoreFavorite(item: FavoriteContentItem) throws
}

extension FavoriteRepository {
    func fetchFavoriteItemIDs() throws -> Set<String> {
        return try self.fetchFavoriteItemIDs(sourceID: nil)
    }
}
