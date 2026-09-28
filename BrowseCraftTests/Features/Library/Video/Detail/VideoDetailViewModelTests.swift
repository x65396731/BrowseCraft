import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

@MainActor
struct VideoDetailViewModelTests {
    @Test func dropsSingletonDuplicateEntryGroup() {
        let chapters: [SourceChapter] = VideoDetailViewModel.filteredEpisodeChapters(
            from: [
                Self.chapter(
                    title: "立即播放",
                    subtitle: "守护解放西6 (2025)",
                    url: "https://video.example.invalid/watch/1"
                ),
                Self.chapter(
                    title: "第01集",
                    subtitle: "播放测试说明",
                    url: "https://video.example.invalid/watch/1"
                ),
                Self.chapter(
                    title: "第02集",
                    subtitle: "播放测试说明",
                    url: "https://video.example.invalid/watch/2"
                )
            ]
        )

        #expect(chapters.map(\.title) == ["第01集", "第02集"])
    }

    @Test func dropsSuspiciousDuplicateEpisodeGroup() {
        let chapters: [SourceChapter] = VideoDetailViewModel.filteredEpisodeChapters(
            from: [
                Self.chapter(title: "第01集", subtitle: "在线播放"),
                Self.chapter(title: "第02集", subtitle: "在线播放"),
                Self.chapter(title: "第03集", subtitle: "在线播放"),
                Self.chapter(title: "第01集", subtitle: "播放测试说明"),
                Self.chapter(title: "第02集", subtitle: "播放测试说明"),
                Self.chapter(title: "第03集", subtitle: "播放测试说明")
            ]
        )

        #expect(chapters.map(\.title) == ["第01集", "第02集", "第03集"])
        #expect(chapters.map(\.subtitle) == ["在线播放", "在线播放", "在线播放"])
    }

    @Test func keepsDuplicateEpisodeGroupsWhenTitlesLookLegitimate() {
        let chapters: [SourceChapter] = VideoDetailViewModel.filteredEpisodeChapters(
            from: [
                Self.chapter(title: "第01集", subtitle: "线路 A"),
                Self.chapter(title: "第02集", subtitle: "线路 A"),
                Self.chapter(title: "第01集", subtitle: "线路 B"),
                Self.chapter(title: "第02集", subtitle: "线路 B")
            ]
        )

        #expect(chapters.map(\.subtitle) == ["线路 A", "线路 A", "线路 B", "线路 B"])
    }

    // 中文注释：2026-09-29 小宝影院——两条线路的选集被接成一份扁平列表、都没有线路名，按重复的第 01 集切成线路。
    @Test func labelsRoutesWhenFlatListRestartsWithoutRouteNames() {
        let chapters: [SourceChapter] = VideoDetailViewModel.filteredEpisodeChapters(
            from: [
                Self.chapter(title: "第01集", subtitle: nil, url: "https://video.example.invalid/1-1"),
                Self.chapter(title: "第02集", subtitle: nil, url: "https://video.example.invalid/1-2"),
                Self.chapter(title: "第01集", subtitle: nil, url: "https://video.example.invalid/2-1"),
                Self.chapter(title: "第02集", subtitle: nil, url: "https://video.example.invalid/2-2")
            ]
        )

        #expect(chapters.count == 4)
        let expectedFirst: String = String(format: NSLocalizedString("video_episode_route_label", comment: ""), 1)
        let expectedSecond: String = String(format: NSLocalizedString("video_episode_route_label", comment: ""), 2)
        #expect(chapters.map(\.subtitle) == [expectedFirst, expectedFirst, expectedSecond, expectedSecond])
    }

    @Test func leavesSingleRouteFlatListUnlabeled() {
        let chapters: [SourceChapter] = VideoDetailViewModel.filteredEpisodeChapters(
            from: [
                Self.chapter(title: "第01集", subtitle: nil),
                Self.chapter(title: "第02集", subtitle: nil),
                Self.chapter(title: "第03集", subtitle: nil)
            ]
        )

        #expect(chapters.map(\.subtitle) == [nil, nil, nil])
    }

    private static func chapter(title: String, subtitle: String?, url: String? = nil) -> SourceChapter {
        let urlString: String = url ?? "https://video.example.invalid/\(title)"
        return SourceChapter(
            id: urlString,
            title: title,
            subtitle: subtitle,
            url: URL(string: urlString)!
        )
    }
}
