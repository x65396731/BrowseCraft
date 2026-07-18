import Foundation
import Testing
@testable import BrowseCraft

struct SwiftSoupListParserTests {
    @Test func v2PageRuleRefsSelectRuleSetsListRule() throws {
        let source: Source = try Self.v2ListRuleSourceWithLegacyListDisabled()
        let parser: SwiftSoupComicRuleSourceParser = SwiftSoupComicRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let items: [ContentItem] = try parser.parseList(
            html: Self.v2ListHTML,
            source: source
        )

        // 中文注释：旧版 list 已被改成无法匹配的 selector；能解析出条目说明默认入口确实走了 V2 Page -> RuleSets。
        #expect(items.count == 2)
        #expect(items[0].title == "V2 第一话")
        #expect(items[0].detailURL == "https://example.test/comics/v2-1")
        #expect(items[0].coverURL == "https://example.test/images/v2-1.jpg")
        #expect(items[1].title == "V2 第二话")
        #expect(items[1].detailURL == "https://example.test/comics/v2-2")

        try Self.assertSearchRuleParsesExtractRuleFields(parser: parser, source: source)
    }

    @Test func v2PageSectionsAttachSectionContextToListItems() throws {
        let source: Source = try Self.v2ListRuleSourceWithLegacyListDisabled()
        let parser: SwiftSoupComicRuleSourceParser = SwiftSoupComicRuleSourceParser(
            urlResolver: URLResolvingService()
        )
        let tab: ListTabRule = try #require(source.rule.availableListTabs.first)

        let items: [ContentItem] = try parser.parseList(
            html: Self.v2SectionListHTML,
            source: source,
            listRule: tab.list,
            context: tab.context,
            sections: tab.sections
        )

        // 中文注释：P1-5.2 要把 PageRule.sections 的来源区块写入 item context，后续详情页可排除推荐区误匹配。
        #expect(items.map(\.title) == ["主列表作品", "推荐作品"])
        #expect(items[0].listContext?.sectionId == "main-grid")
        #expect(items[0].listContext?.sectionRole == .main)
        #expect(items[1].listContext?.sectionId == "recommendations")
        #expect(items[1].listContext?.sectionRole == .recommendation)
        #expect(items[1].listContext?.pageId == "home")
        #expect(items[1].listContext?.tabId == "discover")
        #expect(items[1].listContext?.listRuleId == "home-list")
    }

    @Test func legacyListTitleSelectorUsesFirstNonEmptyMatchedElement() throws {
        let source: Source = Self.legacyListSource()
        let parser: SwiftSoupComicRuleSourceParser = SwiftSoupComicRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let items: [ContentItem] = try parser.parseList(
            html: Self.listWithEmptyCoverAnchorHTML,
            source: source
        )

        #expect(items.count == 1)
        #expect(items[0].title == "下垂眼")
        #expect(items[0].detailURL == "https://example.test/info/xiachuiyan.html")
        #expect(items[0].coverURL == "https://example.test/images/xiachuiyan.jpg")
    }

    @Test func legacyListCoverFallsBackToInlineBackgroundImage() throws {
        let source: Source = Self.legacyListSource()
        let parser: SwiftSoupComicRuleSourceParser = SwiftSoupComicRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let items: [ContentItem] = try parser.parseList(
            html: Self.listWithBackgroundCoverHTML,
            source: source
        )

        #expect(items.count == 1)
        #expect(items[0].title == "背景图作品")
        #expect(items[0].detailURL == "https://example.test/info/background.html")
        #expect(items[0].coverURL == "https://example.test/images/background.jpg")
    }

    @Test func legacyListCoverFallsBackToEmbeddedImageURLMap() throws {
        let source: Source = Self.embeddedURLListSource()
        let parser: SwiftSoupComicRuleSourceParser = SwiftSoupComicRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let items: [ContentItem] = try parser.parseList(
            html: Self.listWithEmbeddedCoverMapHTML,
            source: source
        )

        #expect(items.count == 1)
        #expect(items[0].title == "小栗子到我家")
        #expect(items[0].detailURL == "https://example.test/comic/5571")
        #expect(items[0].coverURL == "https://example.test/images/cover-5571.jpg")
    }

    @Test func legacyListCoverFallsBackToEmbeddedAbsoluteImageURLMap() throws {
        let source: Source = Self.embeddedURLListSource()
        let parser: SwiftSoupComicRuleSourceParser = SwiftSoupComicRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let items: [ContentItem] = try parser.parseList(
            html: Self.listWithEmbeddedAbsoluteCoverMapHTML,
            source: source
        )

        #expect(items.count == 1)
        #expect(items[0].coverURL == "https://img.example.test/cover-5571.jpg")
    }

    @Test func legacyOwnTextAttributeExcludesNestedChapterMetrics() throws {
        var source: Source = Self.legacyListSource()
        source.rule.detail?.chapterContainer = ".chapters"
        source.rule.detail?.chapterItem = ".chapter"
        source.rule.detail?.chapterTitle = ".number@ownText"
        source.rule.detail?.chapterLink = ".reader@href"
        let parser: SwiftSoupComicRuleSourceParser = SwiftSoupComicRuleSourceParser(
            urlResolver: URLResolvingService()
        )

        let chapters: [ChapterLink] = try parser.parseDetailChapters(
            html: """
            <ul class="chapters">
              <li class="chapter">
                <dt class="number">
                  001話
                  <div class="metrics"><span>4.6万</span><a href="/comments">146</a></div>
                </dt>
                <a class="reader" href="/free_chapters/1">無料</a>
              </li>
            </ul>
            """,
            source: source,
            pageURL: "https://example.test/books/1"
        )

        #expect(chapters.map(\.title) == ["001話"])
        #expect(chapters.map(\.url) == ["https://example.test/free_chapters/1"])
    }

    private static let v2ListHTML: String = """
    <main>
      <article class="card" data-id="v2-1">
        <a class="title" href="/comics/v2-1">V2 第一话</a>
        <img class="cover" src="/images/v2-1.jpg">
      </article>
      <article class="card" data-id="v2-2">
        <a class="title" href="/comics/v2-2">V2 第二话</a>
        <img class="cover" src="/images/v2-2.jpg">
      </article>
    </main>
    """

    private static let v2SectionListHTML: String = """
    <main>
      <section class="main-grid">
        <article class="card" data-id="main-1">
          <a class="title" href="/comics/main-1">主列表作品</a>
          <img class="cover" src="/images/main-1.jpg">
        </article>
      </section>
      <section class="recommendations">
        <article class="card" data-id="recommend-1">
          <a class="title" href="/comics/recommend-1">推荐作品</a>
          <img class="cover" src="/images/recommend-1.jpg">
        </article>
      </section>
    </main>
    """

    private static let listWithEmptyCoverAnchorHTML: String = """
    <main>
      <ul class="list_con_li">
        <li>
          <a href="/info/xiachuiyan.html" class="comic_img">
            <img src="/images/xiachuiyan.jpg" alt="下垂眼 漫画封面">
          </a>
          <span class="comic_list_det">
            <h3><a href="/info/xiachuiyan.html">下垂眼</a></h3>
          </span>
        </li>
      </ul>
    </main>
    """

    private static let listWithBackgroundCoverHTML: String = """
    <main>
      <ul class="list_con_li">
        <li>
          <a href="/info/background.html" class="comic_img">
            <div class="v-img__img" style="background-image: url('/images/background.jpg');"></div>
          </a>
          <span class="comic_list_det">
            <h3><a href="/info/background.html">背景图作品</a></h3>
          </span>
        </li>
      </ul>
    </main>
    """

    private static let listWithEmbeddedCoverMapHTML: String = """
    <main>
      <div class="comic-card-wrapper">
        <a href="/comic/5571">小栗子到我家</a>
        <span>连载19话</span>
      </div>
      <script>
        window.__DATA__ = {"items":[{"url":"/comic/5571","title":"小栗子到我家","imageUrl":"/images/cover-5571.jpg"}]};
      </script>
    </main>
    """

    private static let listWithEmbeddedAbsoluteCoverMapHTML: String = """
    <main>
      <div class="comic-card-wrapper">
        <a href="/comic/5571">小栗子到我家</a>
      </div>
      <script>
        window.__DATA__ = {"items":[{"coverUrl":"https:\\/\\/img.example.test\\/cover-5571.jpg","title":"小栗子到我家","href":"\\/comic\\/5571"}]};
      </script>
    </main>
    """

    private static let searchHTML: String = """
    <main>
      <article class="search-result">
        <a class="title" href="/comics/search-1">搜索结果一</a>
      </article>
      <article class="search-result">
        <a class="title" href="/comics/search-2">搜索结果二</a>
      </article>
      <article class="search-result">
        <span class="title">缺少链接的结果</span>
      </article>
      <a class="next" href="/search?q=%E7%8C%AB&page=2">下一页</a>
    </main>
    """

    private static func assertSearchRuleParsesExtractRuleFields(
        parser: SwiftSoupComicRuleSourceParser,
        source: Source
    ) throws {
        let searchRule: SearchRule = try #require(source.rule.ruleSets?.searchRule(id: "search"))
        let context: ListContext = ListContext(
            pageId: "search",
            tabId: nil,
            sectionId: nil,
            listRuleId: searchRule.listRuleRef,
            sectionRole: nil
        )

        let items: [ContentItem] = try parser.parseSearch(
            html: Self.searchHTML,
            source: source,
            searchRule: searchRule,
            context: context
        )

        // 中文注释：SearchRule 使用 ExtractRule 形态的 item/fields，不依赖旧版 ListRule 字符串字段。
        #expect(items.count == 2)
        #expect(items[0].title == "搜索结果一")
        #expect(items[0].detailURL == "https://example.test/comics/search-1")
        #expect(items[0].type == .comic)
        #expect(items[0].listOrder == 0)
        #expect(items[0].listContext?.pageId == "search")
        #expect(items[1].title == "搜索结果二")
        #expect(items[1].detailURL == "https://example.test/comics/search-2")
        #expect(items[1].listOrder == 1)

        let nextPageURL: String? = try parser.parseNextPageURL(
            html: Self.searchHTML,
            source: source,
            pagination: PaginationRule(
                nextPage: ExtractRule(
                    selector: "a.next",
                    selectorKind: nil,
                    function: .url,
                    functions: nil,
                    param: nil,
                    regex: nil,
                    replacement: nil,
                    fallback: nil
                ),
                pagePlaceholder: nil,
                maxPages: 10,
                stopWhenEmpty: true
            ),
            currentURL: URL(string: "https://example.test/search?q=%E7%8C%AB&page=1") ?? URL(fileURLWithPath: "/")
        )

        // 中文注释：P2-6.4 nextPage 抽取只返回下一页 URL，不自动发起第二次请求。
        #expect(nextPageURL == "https://example.test/search?q=%E7%8C%AB&page=2")
    }

    private static func v2ListRuleSourceWithLegacyListDisabled() throws -> Source {
        var rule: SiteRule = try JSONDecoder().decode(
            SiteRule.self,
            from: Data(RuleJSONFixtures.completeV2SiteRule.utf8)
        )

        // 中文注释：禁用旧版 list selector，让测试只能通过 PageRule.ruleRefs.list 指向的 V2 listRules 成功。
        rule.list.item = ".legacy-list-should-not-match"

        return Source(
            id: "v2-list-source",
            name: "V2 List Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func legacyListSource() -> Source {
        let rule: SiteRule = SiteRule(
            version: 1,
            site: nil,
            urlPatterns: nil,
            pages: nil,
            ruleSets: nil,
            sharedRequest: nil,
            flags: nil,
            name: "Legacy List Source",
            baseUrl: "https://example.test",
            list: ListRule(
                id: "legacy-list",
                url: "https://example.test/list",
                item: ".list_con_li > li",
                title: "a@title, a",
                link: "a[href*='/info/']@href",
                cover: "img@src",
                type: .comic,
                latestText: nil
            ),
            listTabs: nil,
            detail: DetailRule(
                id: "detail",
                fields: nil,
                title: "h1",
                cover: nil,
                mainScope: nil,
                exclude: nil,
                chapterRule: nil,
                chapterContainer: nil,
                chapterItem: "a",
                chapterTitle: "this",
                chapterLink: "this@href",
                treatDetailURLAsChapter: nil,
                tagRule: nil,
                pictureRule: nil,
                commentRule: nil,
                videoRule: nil,
                ready: nil,
                request: nil,
                js: nil
            ),
            gallery: GalleryRule(
                id: "reader",
                mainScope: nil,
                item: nil,
                image: nil,
                thumbnail: nil,
                link: nil,
                totalPages: nil,
                secondLevelPageURL: nil,
                variants: nil,
                sourceFiles: nil,
                pagination: nil,
                request: nil,
                js: nil,
                imageItem: "img.page",
                imageUrl: "this@src",
                comicTitle: nil,
                chapterTitle: nil,
                catalogLink: nil,
                previousLink: nil,
                nextLink: nil
            ),
            video: nil
        )

        return Source(
            id: "legacy-list-source",
            name: "Legacy List Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func embeddedURLListSource() -> Source {
        let rule: SiteRule = SiteRule(
            version: 1,
            site: nil,
            urlPatterns: nil,
            pages: nil,
            ruleSets: nil,
            sharedRequest: nil,
            flags: nil,
            name: "Embedded URL Source",
            baseUrl: "https://example.test",
            list: ListRule(
                id: "updates",
                url: "https://example.test/updates",
                item: ".comic-card-wrapper",
                title: "a",
                link: "a@href",
                cover: "img@src",
                type: .comic,
                latestText: nil
            ),
            listTabs: nil,
            detail: DetailRule(
                id: "detail",
                chapterItem: "a",
                chapterTitle: "this",
                chapterLink: "this@href"
            ),
            gallery: GalleryRule(
                id: "reader",
                imageItem: "img.page",
                imageUrl: "this@src"
            ),
            video: nil
        )

        return Source(
            id: "embedded-url-source",
            name: "Embedded URL Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
