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

    /// 中文注释：纪录页三类各一条，时间错开几分钟，按最近观看排序时三类交替出现。
    private func seedHistory(sourcesByID: [String: Source], now: Date) throws {
        let videoSite: DemoSite = DemoContent.videoSite
        if let work: DemoWork = DemoContent.works.first(where: { work in work.number == 1 }) {
            let detailURL: URL = videoSite.detailURL(for: work)
            try self.videoHistoryRepository.save(
                VideoWatchHistory(
                    userID: self.userID,
                    sourceID: videoSite.id,
                    vodID: detailURL.absoluteString,
                    videoTitle: work.title.value,
                    episodeTitle: DemoContent.episodeTitle.formatted(5),
                    episodeKey: "episode-5",
                    sourceIndex: 0,
                    episodeIndex: 4,
                    detailURL: detailURL,
                    playPageURL: detailURL.appendingPathComponent("episode-5"),
                    candidateMediaKind: .unknown,
                    playbackStatus: .pageOnly,
                    coverURL: work.coverURL,
                    sourceName: videoSite.name.value,
                    lastPlaybackTime: 1_260,
                    duration: 2_700,
                    visitedAt: now.addingTimeInterval(-5 * 60),
                    updatedAt: now.addingTimeInterval(-5 * 60),
                    sourceSnapshot: sourcesByID[videoSite.id].map(SourceSnapshot.init(source:))
                )
            )
        }

        let comicSite: DemoSite = DemoContent.comicSite
        if let work: DemoWork = DemoContent.works.first(where: { work in work.number == 6 }) {
            let detailURL: URL = comicSite.detailURL(for: work)
            try self.comicHistoryRepository.save(
                ComicChapterHistory(
                    userID: self.userID,
                    sourceID: comicSite.id,
                    comicItemID: detailURL.absoluteString,
                    comicTitle: work.title.value,
                    chapterID: "chapter-8",
                    chapterKey: "chapter-8",
                    chapterURL: detailURL.appendingPathComponent("chapter-8"),
                    chapterTitle: DemoContent.comicChapterTitle.formatted(8),
                    visitedAt: now.addingTimeInterval(-40 * 60),
                    coverURL: work.coverURL,
                    sourceSnapshot: sourcesByID[comicSite.id].map(SourceSnapshot.init(source:))
                )
            )
        }

        let bookSite: DemoSite = DemoContent.bookSite
        if let work: DemoWork = DemoContent.works.first(where: { work in work.number == 9 }) {
            let detailURL: URL = bookSite.detailURL(for: work)
            try self.bookHistoryRepository.save(
                BookReadingHistory(
                    userID: self.userID,
                    sourceID: bookSite.id,
                    detailURL: detailURL.absoluteString,
                    bookItemID: detailURL.absoluteString,
                    bookTitle: work.title.value,
                    coverURL: work.coverURL,
                    chapterTitle: DemoContent.bookChapterTitle.formatted(3),
                    chapterURL: detailURL.appendingPathComponent("chapter-3"),
                    visitedAt: now.addingTimeInterval(-2 * 60 * 60),
                    sourceSnapshot: sourcesByID[bookSite.id].map(SourceSnapshot.init(source:))
                )
            )
        }
    }
}
#endif
