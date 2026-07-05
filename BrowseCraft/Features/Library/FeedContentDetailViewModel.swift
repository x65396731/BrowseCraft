import Combine
import Foundation

// 中文注释：FeedContentDetailViewModel 负责 RSS 详情页的业务行为。

/// 中文注释：RSS 阅读历史保存放在 ViewModel，View 只负责展示与触发生命周期。
@MainActor
final class FeedContentDetailViewModel: ObservableObject {
    let item: ContentItem
    let source: Source

    private let saveRSSReadingHistoryUseCase: SaveRSSReadingHistoryUseCase
    private let now: () -> Date
    private var didSaveReadingHistory: Bool = false

    init(
        item: ContentItem,
        source: Source,
        saveRSSReadingHistoryUseCase: SaveRSSReadingHistoryUseCase,
        now: @escaping () -> Date = Date.init
    ) {
        self.item = item
        self.source = source
        self.saveRSSReadingHistoryUseCase = saveRSSReadingHistoryUseCase
        self.now = now
    }

    var sourceName: String {
        return self.source.name
    }

    func saveReadingHistoryIfNeeded() {
        if self.didSaveReadingHistory {
            return
        }

        self.didSaveReadingHistory = true

        do {
            try self.saveRSSReadingHistoryUseCase.execute(
                history: self.readingHistory()
            )
            #if DEBUG
            print(
                "[BrowseCraftRSSHistory] saved " +
                "userID=\(AppUser.localDefaultID) " +
                "sourceID=\(self.source.id) " +
                "itemID=\(self.item.id)"
            )
            #endif
        } catch {
            #if DEBUG
            print(
                "[BrowseCraftRSSHistory] save failed " +
                "sourceID=\(self.source.id) " +
                "itemID=\(self.item.id) " +
                "error=\(error)"
            )
            #endif
        }
    }

    private func readingHistory() -> RSSReadingHistory {
        let timestamp: Date = self.now()

        return RSSReadingHistory(
            userID: AppUser.localDefaultID,
            sourceID: self.source.id,
            itemID: self.item.id,
            dataType: .article,
            title: self.item.title,
            dataContent: self.dataContent(),
            dataTime: self.item.updatedAt ?? timestamp,
            visitedAt: timestamp,
            detailURL: URL(string: self.item.detailURL),
            sourceName: self.source.name,
            originFeedURL: self.originFeedURL()
        )
    }

    private func dataContent() -> String {
        if let summary: String = FeedContentTextFormatter.sanitized(self.item.latestText) {
            return summary
        }

        return self.item.title
    }

    private func originFeedURL() -> URL? {
        guard case .rss(let configuration) = self.source.configuration else {
            return URL(string: self.source.baseURL)
        }

        return configuration.definition.feedURL
    }
}
