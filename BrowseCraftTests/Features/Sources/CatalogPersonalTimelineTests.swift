import Foundation
import Testing
@testable import BrowseCraft
import BrowseCraftDomain

/// 规则目录页方案 A 的两处纯逻辑：「我的生成」时间线的排序与按天分组，推荐按类型分区。
struct CatalogPersonalTimelineTests {
    private static let calendar: Calendar = {
        var calendar: Calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 2026-09-30 15:00 JST
    private static let now: Date = Date(timeIntervalSince1970: 1_790_748_000)

    @Test("成功与失败合并成一条线，按终结时间倒序，按今天 / 昨天 / 日期 / 更早分组")
    func mergesSuccessAndFailureNewestFirstGroupedByDay() {
        let today: CatalogSource = Self.source(id: "today")
        let older: CatalogSource = Self.source(id: "older")
        let undated: CatalogSource = Self.source(id: "undated")
        let failedYesterday: VideoGenerationOutcome = Self.outcome(status: "failed", finishedAt: "2026-09-29T10:00:00Z")
        let grouping: CatalogSourceGrouping = CatalogSourceGrouping(
            defaultSources: [],
            personalSources: [older, undated, today],
            failedOutcomes: [failedYesterday],
            personalOutcomes: [
                "today": Self.outcome(status: "succeeded", finishedAt: "2026-09-30T03:00:00Z", catalogSourceID: "today"),
                "older": Self.outcome(status: "succeeded", finishedAt: "2026-09-26T03:00:00Z", catalogSourceID: "older"),
                "undated": Self.outcome(status: "succeeded", finishedAt: nil, catalogSourceID: "undated")
            ]
        )

        let timeline: CatalogPersonalTimeline = CatalogPersonalTimeline.make(
            grouping: grouping,
            now: Self.now,
            calendar: Self.calendar
        )

        #expect(timeline.groups.map(\.day) == [
            .today,
            .yesterday,
            .date(Self.calendar.startOfDay(for: Self.date("2026-09-26T03:00:00Z"))),
            .unknown
        ])
        #expect(timeline.groups.flatMap(\.entries).map(\.id) == [
            "rule-today",
            "failure-\(failedYesterday.jobID.uuidString)",
            "rule-older",
            "rule-undated"
        ])
    }

    @Test("没有任何个人条目时时间线为空")
    func emptyGroupingGivesEmptyTimeline() {
        let grouping: CatalogSourceGrouping = CatalogSourceGrouping(
            defaultSources: [Self.source(id: "public")],
            personalSources: [],
            failedOutcomes: [],
            personalOutcomes: [:]
        )

        #expect(CatalogPersonalTimeline.make(grouping: grouping, now: Self.now, calendar: Self.calendar).isEmpty)
    }

    @Test("推荐按 视频 → 漫画 → 书籍 分区，空类型不出现，区内保持服务端顺序")
    func recommendationsAreSectionedByKindInFixedOrder() {
        let sections: [CatalogKindSection] = CatalogKindSection.make([
            Self.source(id: "book-1", kind: .book),
            Self.source(id: "video-1", kind: .video),
            Self.source(id: "book-2", kind: .book),
            Self.source(id: "video-2", kind: .video)
        ])

        #expect(sections.map(\.kind) == [.video, .book])
        #expect(sections.map { $0.sources.map(\.id) } == [["video-1", "video-2"], ["book-1", "book-2"]])
    }

    @Test("首字徽标取第一个字符，拉丁字母大写；副标题只给主机名，同站多条时补路径尾段")
    func displayTextHelpers() {
        #expect(CatalogDisplayText.monogram(for: "dytiantang.tv · 古装") == "D")
        #expect(CatalogDisplayText.monogram(for: "威视 TV") == "威")
        #expect(CatalogDisplayText.recommendationSubtitle(baseURL: "https://book.sfacg.com/", entryURL: nil) == "book.sfacg.com")
        #expect(
            CatalogDisplayText.recommendationSubtitle(
                baseURL: "https://book.sfacg.com/",
                entryURL: "https://book.sfacg.com/List/?tid=21"
            ) == "book.sfacg.com · List?tid=21"
        )
        let parts: (host: String, rest: String) = CatalogDisplayText.addressParts(
            of: "https://weishitv.xyz/index.php/vod/show/area/%E5%8F%B0%E6%B9%BE/id/2.html"
        )
        #expect(parts.host == "weishitv.xyz")
        #expect(parts.rest == "/index.php/vod/show/area/台湾/id/2.html")
    }

    @Test("保留期比例夹在 0...1")
    func remainingFractionIsClamped() {
        let now: Date = Self.now
        #expect(PersonalRuleRetentionPolicy.remainingFraction(expiresAt: now.addingTimeInterval(-60), now: now) == 0)
        #expect(PersonalRuleRetentionPolicy.remainingFraction(
            expiresAt: now.addingTimeInterval(PersonalRuleRetentionPolicy.visibleDuration * 2),
            now: now
        ) == 1)
        #expect(abs(PersonalRuleRetentionPolicy.remainingFraction(
            expiresAt: now.addingTimeInterval(PersonalRuleRetentionPolicy.visibleDuration / 2),
            now: now
        ) - 0.5) < 0.0001)
    }

    private static func source(id: String, kind: CatalogSourceKind = .video) -> CatalogSource {
        return CatalogSource(id: id, name: id, baseURL: "https://\(id).example/", kind: kind, ruleJSON: "{}")
    }

    private static func outcome(
        status: String,
        finishedAt: String?,
        catalogSourceID: String? = nil
    ) -> VideoGenerationOutcome {
        return VideoGenerationOutcome(
            jobID: UUID(),
            entryURL: "https://example.com/list/1.html",
            status: status,
            finishedAt: finishedAt,
            catalogSourceID: catalogSourceID,
            reason: status == "failed" ? "siteNotSupported" : nil,
            reasonDetail: nil
        )
    }

    private static func date(_ iso: String) -> Date {
        return ISO8601DateFormatter().date(from: iso)!
    }
}
