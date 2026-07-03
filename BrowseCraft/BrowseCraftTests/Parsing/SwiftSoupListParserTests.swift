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
}
