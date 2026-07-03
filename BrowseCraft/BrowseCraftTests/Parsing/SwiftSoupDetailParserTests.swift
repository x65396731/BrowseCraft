import Testing
@testable import BrowseCraft

// 中文注释：详情页章节解析回归测试，重点保护章节作用域和误匹配防护。
struct SwiftSoupDetailParserTests {
    @Test func builtInDetailRuleParsesOnlyScopedChapters() throws {
        let source: Source = BuiltInSource.primaryBuiltIn()
        let parser: SwiftSoupRuleParser = SwiftSoupRuleParser(
            urlResolver: URLResolvingService()
        )

        let chapters: [ChapterLink] = try parser.parseDetailChapters(
            html: BuiltInRuleHTMLFixtures.detailHTML,
            source: source,
            pageURL: "https://example.test/cn/comics/55355"
        )

        // 中文注释：章节解析必须限定在规则指定容器内，避免把排行或推荐区域误识别为作品章节。
        #expect(chapters.count == 2)
        #expect(chapters[0].title == "第02话")
        #expect(chapters[0].url == "https://example.test/cn/chapters/818145")
        #expect(chapters[1].title == "第01话")
        #expect(chapters[1].url == "https://example.test/cn/chapters/818144")
    }

    @Test func builtInDetailRuleDoesNotFallbackToGlobalChapterLinks() throws {
        let source: Source = BuiltInSource.primaryBuiltIn()
        let parser: SwiftSoupRuleParser = SwiftSoupRuleParser(
            urlResolver: URLResolvingService()
        )

        let chapters: [ChapterLink] = try parser.parseDetailChapters(
            html: BuiltInRuleHTMLFixtures.detailHTMLWithoutChapterContainer,
            source: source,
            pageURL: "https://example.test/cn/comics/55355"
        )

        // 中文注释：缺少章节容器时应返回空数组，不能退回全页面 a[href*=chapters] 的宽泛匹配。
        #expect(chapters.isEmpty)
    }
}
