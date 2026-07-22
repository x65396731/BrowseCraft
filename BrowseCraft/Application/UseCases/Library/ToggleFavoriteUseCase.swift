import Foundation

// 中文注释：ToggleFavoriteUseCase.swift 属于应用用例层，用于说明本文件承载的核心职责。

/// 中文注释：读取并切换单个内容条目的收藏状态。
struct ToggleFavoriteUseCase {
    private let favoriteRepository: FavoriteRepository

    init(favoriteRepository: FavoriteRepository) {
        self.favoriteRepository = favoriteRepository
    }

    /// 中文注释：loadFavoriteItemIDs 方法封装当前类型的一段业务或界面行为。
    func loadFavoriteItemIDs(sourceID: String?) throws -> Set<String> {
        return try self.favoriteRepository.fetchFavoriteItemIDs(sourceID: sourceID)
    }

    func loadFavoriteItems() throws -> [FavoriteContentItem] {
        return try self.favoriteRepository.fetchFavoriteItems()
    }

    /// 中文注释：收藏快照的物化属于收藏用例，不由 LibraryViewModel 或 runtime mapping 承担。
    func execute(
        item: ContentItem,
        source: Source?,
        favoritedAt: Date
    ) throws -> Set<String> {
        let favoriteItem: FavoriteContentItem = self.favoriteItem(
            from: item,
            source: source,
            favoritedAt: favoritedAt
        )
        let currentIDs: Set<String> = try self.favoriteRepository.fetchFavoriteItemIDs(
            sourceID: favoriteItem.sourceID
        )
        let shouldBecomeFavorite: Bool = !currentIDs.contains(favoriteItem.id)

        try self.favoriteRepository.setFavorite(item: favoriteItem, isFavorite: shouldBecomeFavorite)
        return try self.favoriteRepository.fetchFavoriteItemIDs(sourceID: favoriteItem.sourceID)
    }

    private func favoriteItem(
        from item: ContentItem,
        source: Source?,
        favoritedAt: Date
    ) -> FavoriteContentItem {
        return FavoriteContentItem(
            id: item.id,
            idCode: item.idCode,
            sourceID: item.sourceId,
            title: item.title,
            detailURL: item.detailURL,
            coverURL: item.coverURL,
            kind: self.favoriteKind(for: item),
            latestText: item.latestText,
            updatedAt: item.updatedAt,
            favoritedAt: favoritedAt,
            listOrder: item.listOrder,
            listContext: item.listContext,
            sourceSnapshot: source.map(FavoriteSourceSnapshot.init(source:))
        )
    }

    private func favoriteKind(for item: ContentItem) -> FavoriteContentKind {
        switch item.type {
        case .article:
            return .rss
        case .comic:
            return .comic
        case .video:
            return .videoNative
        default:
            return .rss
        }
    }
}
