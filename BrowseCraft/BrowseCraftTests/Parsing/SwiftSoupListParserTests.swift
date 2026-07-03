import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：列表解析回归测试，确认内置规则仍能从列表页抽出卡片数据。
struct SwiftSoupListParserTests {
    @Test func builtInListRuleParsesComicCards() throws {
        let source: Source = BuiltInSource.primaryBuiltIn()
        let parser: SwiftSoupRuleParser = SwiftSoupRuleParser(
            urlResolver: URLResolvingService()
        )

        let items: [ContentItem] = try parser.parseList(
            html: BuiltInRuleHTMLFixtures.listHTML,
            source: source
        )

        // 中文注释：列表解析要保留卡片顺序，并从链接、图片和 badge 中抽出进入详情页所需的最小字段。
        #expect(items.count == 2)
        #expect(items[0].title == "猎人游戏W")
        #expect(items[0].detailURL == "https://example.test/cn/comics/55355")
        #expect(items[0].coverURL == "https://image.example/comics/55355-9e7018.jpg")
        #expect(items[0].latestText == "第07话")
        #expect(items[1].title == "1步前进 2步后退")
        #expect(items[1].latestText == "短篇 [完]")
    }

    @Test func v2PageRuleRefsSelectRuleSetsListRule() throws {
        let source: Source = try Self.v2ListRuleSourceWithLegacyListDisabled()
        let parser: SwiftSoupRuleParser = SwiftSoupRuleParser(
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
}
