import Foundation
import Testing
@testable import BrowseCraft

struct SwiftSoupReaderParserTests {
    @Test func v2PageRuleRefsSelectRuleSetsGalleryRule() throws {
        let source: Source = try Self.v2GalleryRuleSourceWithLegacyGalleryDisabled()
        let parser: SwiftSoupRuleSourceParser = SwiftSoupRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let chapter: ReaderChapter = try parser.parseReader(
            html: """
            <main>
              <img class="page" data-src="/images/v2-page-1.jpg" src="/placeholder.gif">
              <img class="page" data-src="/images/v2-page-2.jpg" src="/placeholder.gif">
            </main>
            """,
            source: source,
            pageURL: "https://example.test/chapters/v2"
        )

        // 中文注释：旧版 gallery 已置空；能解析出图片说明默认入口确实走了 V2 Page -> RuleSets.galleryRules。
        #expect(chapter.pageImageURLs.count == 2)
        #expect(chapter.pageImageURLs[0] == "https://example.test/images/v2-page-1.jpg")
        #expect(chapter.pageImageURLs[1] == "https://example.test/images/v2-page-2.jpg")
    }

    @Test func v2ReaderImagesUseListContextScope() throws {
        let source: Source = try Self.v2GalleryRuleSourceWithLegacyGalleryDisabled()
        let parser: SwiftSoupRuleSourceParser = SwiftSoupRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let chapter: ReaderChapter = try parser.parseReader(
            html: """
            <main class="reader">
              <section data-section-id="main-grid" data-section-role="main">
                <img class="page" data-src="/images/main-page-1.jpg" src="/placeholder.gif">
              </section>
              <section data-section-id="recommendations" data-section-role="recommendation">
                <img class="page" data-src="/images/recommend-page-1.jpg" src="/placeholder.gif">
              </section>
            </main>
            """,
            source: source,
            pageURL: "https://example.test/chapters/v2",
            context: ListContext(
                pageId: "home",
                tabId: "home",
                sectionId: "main-grid",
                listRuleId: "home-list",
                sectionRole: .main
            )
        )

        // 中文注释：P1-5.3 阅读页图片解析应沿用列表来源 section，避免推荐区图片混入正文。
        #expect(chapter.pageImageURLs == ["https://example.test/images/main-page-1.jpg"])
    }

    @Test func v2PageRuleRefsDriveListDetailAndReaderParsing() throws {
        let source: Source = try Self.v2RuleSourceWithLegacyEntrypointsDisabled()
        let parser: SwiftSoupRuleSourceParser = SwiftSoupRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let items: [ContentItem] = try parser.parseList(
            html: """
            <main>
              <article class="card">
                <a class="title" href="/comics/v2-flow">V2 Flow</a>
                <img class="cover" src="/images/v2-flow-cover.jpg">
              </article>
            </main>
            """,
            source: source
        )

        let chapters: [ChapterLink] = try parser.parseDetailChapters(
            html: """
            <main>
              <div class="chapter" data-id="301" data-cid="401">
                <span class="chapter-title">V2 Flow 第01话</span>
                <a class="chapter-link" href="/chapters/v2-flow-1">Read</a>
              </div>
            </main>
            """,
            source: source,
            pageURL: items[0].detailURL
        )

        let chapter: ReaderChapter = try parser.parseReader(
            html: """
            <main>
              <img class="page" data-src="/images/v2-flow-page-1.jpg">
            </main>
            """,
            source: source,
            pageURL: chapters[0].url
        )

        // 中文注释：同一个 V2 rule fixture 禁用了旧 list/detail/gallery，三段都成功说明 Page/RuleSets 主入口已贯通。
        #expect(items.count == 1)
        #expect(items[0].title == "V2 Flow")
        #expect(items[0].detailURL == "https://example.test/comics/v2-flow")
        #expect(chapters.count == 1)
        #expect(chapters[0].title == "V2 Flow 第01话")
        #expect(chapters[0].url == "https://example.test/chapters/v2-flow-1")
        #expect(chapter.pageImageURLs == ["https://example.test/images/v2-flow-page-1.jpg"])
    }

    private static func v2GalleryRuleSourceWithLegacyGalleryDisabled() throws -> Source {
        var rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )

        // 中文注释：禁用旧版 gallery 字段，让测试只能通过 PageRule.ruleRefs.gallery 指向的 V2 galleryRules 成功。
        rule.gallery = nil

        return Source(
            id: "v2-gallery-source",
            name: "V2 Gallery Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func v2RuleSourceWithLegacyEntrypointsDisabled() throws -> Source {
        var rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )

        // 中文注释：禁用旧入口字段，保证完整流程只能通过 V2 Pages 和 RuleSets 找到执行规则。
        rule.list.item = ".legacy-list-should-not-match"
        rule.detail = nil
        rule.gallery = nil

        return Source(
            id: "v2-flow-source",
            name: "V2 Flow Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
