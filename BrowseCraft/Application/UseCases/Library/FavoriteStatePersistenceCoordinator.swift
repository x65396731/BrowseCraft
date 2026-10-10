import BrowseCraftDomain
import Foundation

/// 中文注释：详情页的收藏读写离开主线程（2026-10-10 复审 B-3）。三个详情 ViewModel 都是 `@MainActor`，
/// 直接调 `ToggleFavoriteUseCase` 会在主线程跑 GRDB 读写事务；云同步写者持锁时主线程会等。
/// 每个 ViewModel 在 init 里从注入的用例自建一个，装配根与测试替身不用改。
actor FavoriteStatePersistenceCoordinator {
    private let useCase: ToggleFavoriteUseCase

    init(useCase: ToggleFavoriteUseCase) {
        self.useCase = useCase
    }

    func isFavorite(itemID: String, sourceID: String) throws -> Bool {
        return try self.useCase.loadFavoriteItemIDs(sourceID: sourceID).contains(itemID)
    }

    /// 切换后该条是否为已收藏。
    func toggle(item: ContentItem, source: Source, favoritedAt: Date) throws -> Bool {
        return try self.useCase.execute(item: item, source: source, favoritedAt: favoritedAt).contains(item.id)
    }
}
