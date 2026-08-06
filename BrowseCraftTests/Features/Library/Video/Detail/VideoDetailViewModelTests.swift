import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

struct VideoDetailViewModelTests {
    @Test func hidesRepeatedEpisodeSubtitleWhenAllRowsShareOneValue() {
        let subtitles: [String?] = VideoDetailViewModel.normalizedEpisodeSubtitles(
            from: [
                Self.chapter(title: "S6_EP6", subtitle: "播放测试说明"),
                Self.chapter(title: "S6_EP9", subtitle: "播放测试说明"),
                Self.chapter(title: "S6_EP10", subtitle: "播放测试说明")
            ]
        )

        #expect(subtitles == [nil, nil, nil])
    }

    @Test func keepsEpisodeSubtitleWhenMultipleGroupsExist() {
        let subtitles: [String?] = VideoDetailViewModel.normalizedEpisodeSubtitles(
            from: [
                Self.chapter(title: "Episode 1", subtitle: "线路 A"),
                Self.chapter(title: "Episode 2", subtitle: "线路 B"),
                Self.chapter(title: "Episode 3", subtitle: "线路 A")
            ]
        )

        #expect(subtitles == ["线路 A", "线路 B", "线路 A"])
    }

    @Test func hidesSingleRepeatedSubtitleButKeepsUniqueSubtitle() {
        let subtitles: [String?] = VideoDetailViewModel.normalizedEpisodeSubtitles(
            from: [
                Self.chapter(title: "立即播放", subtitle: "守护解放西6 (2025)"),
                Self.chapter(title: "S6_EP6", subtitle: "播放测试说明"),
                Self.chapter(title: "S6_EP9", subtitle: "播放测试说明")
            ]
        )

        #expect(subtitles == ["守护解放西6 (2025)", nil, nil])
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

    private static func chapter(title: String, subtitle: String?) -> SourceChapter {
        return SourceChapter(
            title: title,
            subtitle: subtitle,
            url: "https://video.example.invalid/\(title)"
        )
    }
}
