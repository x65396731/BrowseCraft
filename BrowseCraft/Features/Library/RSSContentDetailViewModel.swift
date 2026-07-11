import Combine
import Foundation

// 中文注释：RSSContentDetailViewModel 负责 RSS 详情页的业务行为。

/// 中文注释：RSS 阅读历史保存放在 ViewModel，View 只负责展示与触发生命周期。
@MainActor
final class RSSContentDetailViewModel: ObservableObject {
    @Published private(set) var shouldPlayAd: Bool = false

    let item: ContentItem
    let source: Source

    private let saveRSSReadingHistoryUseCase: SaveRSSReadingHistoryUseCase
    private let accumulateAdPointsUseCase: AccumulateAdPointsUseCase?
    private let now: () -> Date
    private var didSaveReadingHistory: Bool = false

    init(
        item: ContentItem,
        source: Source,
        saveRSSReadingHistoryUseCase: SaveRSSReadingHistoryUseCase,
        accumulateAdPointsUseCase: AccumulateAdPointsUseCase? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.item = item
        self.source = source
        self.saveRSSReadingHistoryUseCase = saveRSSReadingHistoryUseCase
        self.accumulateAdPointsUseCase = accumulateAdPointsUseCase
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
            self.accumulateAdPoints(points: AdPointRule.rssPoints)
            AppAnalytics.shared.logReaderOpened(source: self.source)
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

    func markAdPlaybackHandled() {
        #if DEBUG
        print(
            "[BrowseCraftAdPlayback] RSS mark handled " +
            "sourceID=\(self.source.id) itemID=\(self.item.id) previousShouldPlayAd=\(self.shouldPlayAd)"
        )
        #endif
        self.shouldPlayAd = false
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
            originFeedURL: self.originFeedURL(),
            sourceSnapshot: SourceSnapshot(source: self.source)
        )
    }

    private func dataContent() -> String {
        if let summary: String = RSSContentTextFormatter.sanitized(self.item.latestText) {
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

    private func accumulateAdPoints(points: Int) {
        guard let accumulateAdPointsUseCase: AccumulateAdPointsUseCase = self.accumulateAdPointsUseCase else {
            return
        }

        do {
            let result: AdPointAccumulationResult = try accumulateAdPointsUseCase.execute(points: points)
            #if DEBUG
            print(
                "[BrowseCraftAdPoints] RSS result " +
                "sourceID=\(self.source.id) itemID=\(self.item.id) " +
                "\(result.debugDescription)"
            )
            #endif
            if result.shouldPlayAd {
                #if DEBUG
                print(
                    "[BrowseCraftAdPlayback] RSS shouldPlayAd=true " +
                    "sourceID=\(self.source.id) itemID=\(self.item.id)"
                )
                #endif
                self.shouldPlayAd = true
            }
        } catch {
            #if DEBUG
            print(
                "[BrowseCraftAdPoints] RSS accumulate failed " +
                "sourceID=\(self.source.id) " +
                "itemID=\(self.item.id) " +
                "error=\(error)"
            )
            #endif
        }
    }
}
