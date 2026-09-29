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

    @Test("规则展示信息：真实书籍规则取到分类与语言，带搜索页的规则算可搜索、搜索页不算分类")
    func ruleFactsFromRealBookFixtures() throws {
        let plain: CatalogSource = try ViewModelTestHarness.makeBookCatalogSource(fixture: "biquhua-catalog")
        let withSearch: CatalogSource = try ViewModelTestHarness.makeBookCatalogSource(fixture: "biquhua-catalog-search")

        let plainFacts: CatalogRuleFacts = try #require(CatalogRuleFacts.make(ruleJSON: plain.ruleJSON))
        #expect(plainFacts.categoryTitles == ["最新小说总榜"])
        #expect(plainFacts.supportsSearch == false)
        #expect(plainFacts.language == "zh-Hans")

        let searchFacts: CatalogRuleFacts = try #require(CatalogRuleFacts.make(ruleJSON: withSearch.ruleJSON))
        #expect(searchFacts.categoryTitles == ["最新小说总榜"])
        #expect(searchFacts.supportsSearch)
    }

    @Test("规则展示信息与 kind 无关：多个列表页按顺序去重去空，非列表页不算分类；解析不了返回 nil")
    func ruleFactsAreKindNeutral() throws {
        let ruleJSON: String = """
        {"site": {"language": " ja ", "iconURL": "https://x.example/favicon.ico"},
         "pages": [
           {"type": "list", "title": "全部"},
           {"type": "category", "title": "动作"},
           {"type": "list", "title": "全部"},
           {"type": "list", "title": "  "},
           {"type": "detail", "title": "详情"}
         ],
         "ruleSets": {"searchRules": []}}
        """
        let facts: CatalogRuleFacts = try #require(CatalogRuleFacts.make(ruleJSON: ruleJSON))
        #expect(facts.categoryTitles == ["全部", "动作"])
        #expect(facts.supportsSearch == false)
        #expect(facts.language == "ja")
        #expect(CatalogRuleFacts.make(ruleJSON: "not json") == nil)

        let index: [String: CatalogRuleFacts] = CatalogRuleFacts.makeIndex([
            CatalogSource(id: "a", name: "a", baseURL: "https://a.example/", kind: .comic, ruleJSON: ruleJSON),
            CatalogSource(id: "b", name: "b", baseURL: "https://b.example/", kind: .video, ruleJSON: "not json")
        ])
        #expect(index.keys.sorted() == ["a"])
    }

    @Test("分类行：前三个用 · 连接，其余写 +N；没有分类时为 nil")
    func categorySummary() {
        let many: CatalogRuleFacts = CatalogRuleFacts(
            categoryTitles: ["全部", "动作", "喜剧", "爱情", "科幻"],
            supportsSearch: true,
            language: nil
        )
        #expect(many.categorySummary() == "全部 · 动作 · 喜剧 +2")
        #expect(CatalogRuleFacts(categoryTitles: ["最新小说总榜"], supportsSearch: false, language: nil)
            .categorySummary() == "最新小说总榜")
        #expect(CatalogRuleFacts(categoryTitles: [], supportsSearch: false, language: nil).categorySummary() == nil)
    }

    @Test("语言归一：zh / cmn 按显式文字或台港澳地区分简繁，其余只看语言代码")
    func languageNormalization() {
        #expect(CatalogLanguage(identifier: "zh-Hans") == .chinese(traditional: false))
        #expect(CatalogLanguage(identifier: "cmn-Hans-HK") == .chinese(traditional: false))
        #expect(CatalogLanguage(identifier: "zh-Hant") == .chinese(traditional: true))
        #expect(CatalogLanguage(identifier: "cmn-Hant-TW") == .chinese(traditional: true))
        #expect(CatalogLanguage(identifier: "zh-TW") == .chinese(traditional: true))
        #expect(CatalogLanguage(identifier: "zh_CN") == .chinese(traditional: false))
        #expect(CatalogLanguage(identifier: "en-US") == .other(code: "en"))
        #expect(CatalogLanguage(identifier: "") == nil)
    }

    @Test("语言标签：与 App 界面语言相同时不标，其余给出本地化名称")
    func languageTagHidesTheAppLanguage() {
        #expect(CatalogLanguage.tag(for: "cmn-Hans-HK", appLanguage: "zh-Hans") == nil)
        #expect(CatalogLanguage.tag(for: "en", appLanguage: "en") == nil)
        #expect(CatalogLanguage.tag(for: "cmn-Hant-TW", appLanguage: "zh-Hans") != nil)
        #expect(CatalogLanguage.tag(for: "ja", appLanguage: "en") == "Japanese")
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
