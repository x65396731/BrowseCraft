#if DEBUG
import BrowseCraftDomain
import Foundation

/// 中文注释：演示模式启动时往空的 demo.sqlite 写入演示数据，全部经由正式的仓储写入，
/// 页面读到的就是和真实使用时同一条路径。
struct DemoDataSeeder {
    let sourceRepository: SourceRepository
    let videoHistoryRepository: VideoWatchHistoryRepository
    let comicHistoryRepository: ComicChapterHistoryRepository
    let bookHistoryRepository: BookReadingHistoryRepository
    let userID: String

    func seed() throws {
        let materializer: CatalogSourceMaterializer = CatalogSourceMaterializer()
        let now: Date = Date()
        var sourcesByID: [String: Source] = [:]
        for site: DemoSite in DemoContent.sites {
            let source: Source = try materializer.source(
                from: DemoContent.catalogSource(for: site),
                createdAt: now,
                updatedAt: now
            )
            try self.sourceRepository.saveSource(source)
            sourcesByID[site.id] = source
        }

        try self.seedHistory(sourcesByID: sourcesByID, now: now)
    }

    /// 中文注释：纪录页三类交替出现：今天三条（最近一条是视频，成为「上次看到」），昨天两条、更早两条，
    /// 历史页才有按天分组的样子。昨天 / 更早按日历日算，不随拍图时刻漂到别的分组。
    private func seedHistory(sourcesByID: [String: Source], now: Date) throws {
        let startOfToday: Date = Calendar.current.startOfDay(for: now)
        let yesterdayEvening: Date = startOfToday.addingTimeInterval(-3 * 60 * 60)
        let earlierEvening: Date = startOfToday.addingTimeInterval(-2 * 24 * 60 * 60 + 20 * 60 * 60)

        try self.saveVideo(work: 1, episode: 5, playedSeconds: 1_260, durationSeconds: 2_700,
                           visitedAt: now.addingTimeInterval(-5 * 60), sourcesByID: sourcesByID)
        try self.saveComic(work: 6, chapter: 8, pageIndex: 16, pageCount: 32,
                           visitedAt: now.addingTimeInterval(-40 * 60), sourcesByID: sourcesByID)
        try self.saveBook(work: 9, chapter: 3,
                          visitedAt: now.addingTimeInterval(-2 * 60 * 60), sourcesByID: sourcesByID)
        try self.saveVideo(work: 2, episode: 3, playedSeconds: 760, durationSeconds: 2_640,
                           visitedAt: yesterdayEvening, sourcesByID: sourcesByID)
        try self.saveComic(work: 7, chapter: 21, pageIndex: 8, pageCount: 28,
                           visitedAt: yesterdayEvening.addingTimeInterval(-50 * 60), sourcesByID: sourcesByID)
        try self.saveBook(work: 12, chapter: 15,
                          visitedAt: earlierEvening, sourcesByID: sourcesByID)
        try self.saveVideo(work: 4, episode: 8, playedSeconds: 1_980, durationSeconds: 2_520,
                           visitedAt: earlierEvening.addingTimeInterval(-90 * 60), sourcesByID: sourcesByID)
    }

    private func saveVideo(
        work number: Int,
        episode: Int,
        playedSeconds: Double,
        durationSeconds: Double,
        visitedAt: Date,
        sourcesByID: [String: Source]
    ) throws {
        let site: DemoSite = DemoContent.videoSite
        guard let work: DemoWork = DemoContent.works.first(where: { work in work.number == number }) else {
            return
        }
        let detailURL: URL = site.detailURL(for: work)
        try self.videoHistoryRepository.save(
            VideoWatchHistory(
                userID: self.userID,
                sourceID: site.id,
                vodID: detailURL.absoluteString,
                videoTitle: work.title.value,
                episodeTitle: DemoContent.episodeTitle.formatted(episode),
                episodeKey: "episode-\(episode)",
                sourceIndex: 0,
                episodeIndex: episode - 1,
                detailURL: detailURL,
                playPageURL: detailURL.appendingPathComponent("episode-\(episode)"),
                candidateMediaKind: .unknown,
                playbackStatus: .pageOnly,
                coverURL: work.coverURL,
                sourceName: site.name.value,
                lastPlaybackTime: playedSeconds,
                duration: durationSeconds,
                visitedAt: visitedAt,
                updatedAt: visitedAt,
                sourceSnapshot: sourcesByID[site.id].map(SourceSnapshot.init(source:))
            )
        )
    }

    /// 中文注释：带上页码，库页「上次读到」瓷砖与历史行才有「8 · 17 / 32 页」这样的完整进度。
    private func saveComic(
        work number: Int,
        chapter: Int,
        pageIndex: Int,
        pageCount: Int,
        visitedAt: Date,
        sourcesByID: [String: Source]
    ) throws {
        let site: DemoSite = DemoContent.comicSite
        guard let work: DemoWork = DemoContent.works.first(where: { work in work.number == number }) else {
            return
        }
        let detailURL: URL = site.detailURL(for: work)
        try self.comicHistoryRepository.save(
            ComicChapterHistory(
                userID: self.userID,
                sourceID: site.id,
                comicItemID: detailURL.absoluteString,
                comicTitle: work.title.value,
                chapterID: "chapter-\(chapter)",
                chapterKey: "chapter-\(chapter)",
                chapterURL: detailURL.appendingPathComponent("chapter-\(chapter)"),
                chapterTitle: DemoContent.comicChapterTitle.formatted(chapter),
                visitedAt: visitedAt,
                coverURL: work.coverURL,
                lastPageIndex: pageIndex,
                pageCount: pageCount,
                sourceSnapshot: sourcesByID[site.id].map(SourceSnapshot.init(source:))
            )
        )
    }

    private func saveBook(
        work number: Int,
        chapter: Int,
        visitedAt: Date,
        sourcesByID: [String: Source]
    ) throws {
        let site: DemoSite = DemoContent.bookSite
        guard let work: DemoWork = DemoContent.works.first(where: { work in work.number == number }) else {
            return
        }
        let detailURL: URL = site.detailURL(for: work)
        try self.bookHistoryRepository.save(
            BookReadingHistory(
                userID: self.userID,
                sourceID: site.id,
                detailURL: detailURL.absoluteString,
                bookItemID: detailURL.absoluteString,
                bookTitle: work.title.value,
                coverURL: work.coverURL,
                chapterTitle: DemoContent.bookChapterTitle.formatted(chapter),
                chapterURL: detailURL.appendingPathComponent("chapter-\(chapter)"),
                visitedAt: visitedAt,
                sourceSnapshot: sourcesByID[site.id].map(SourceSnapshot.init(source:))
            )
        )
    }
}
#endif
