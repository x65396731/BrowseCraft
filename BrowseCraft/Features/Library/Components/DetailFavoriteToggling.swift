import BrowseCraftDomain
import Foundation

/// 三个详情页右上收藏按钮的同一套逻辑（2026-10-11 复审「跨页复制」收敛，此前三份逐字相同）：
/// 读当前状态、切换并记埋点；失败只记日志，状态不动。读写都走 `FavoriteStatePersistenceCoordinator`，不在主线程跑 GRDB（复审 B-3）。
@MainActor
protocol DetailFavoriteToggling: AnyObject {
    var item: ContentItem { get }
    var source: Source { get }
    var isFavorite: Bool { get set }
    var favoritePersistence: FavoriteStatePersistenceCoordinator? { get }
    var now: () -> Date { get }
    /// 日志事件名，如 `comic-detail-favorite-error`。
    static var favoriteLogEvent: String { get }
}

extension DetailFavoriteToggling {
    func reloadFavoriteState() async {
        guard let persistence: FavoriteStatePersistenceCoordinator = self.favoritePersistence else {
            return
        }
        do {
            self.isFavorite = try await persistence.isFavorite(itemID: self.item.id, sourceID: self.source.id)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: Self.favoriteLogEvent)
        }
    }

    func toggleFavorite() async {
        guard let persistence: FavoriteStatePersistenceCoordinator = self.favoritePersistence else {
            return
        }
        do {
            let wasFavorite: Bool = self.isFavorite
            self.isFavorite = try await persistence.toggle(item: self.item, source: self.source, favoritedAt: self.now())
            AppAnalytics.shared.logBookmarkChanged(isFavorite: wasFavorite == false, source: self.source)
        } catch {
            RuleExecutionErrorClassifier.log(error: error, stage: .detail, event: Self.favoriteLogEvent)
        }
    }
}
