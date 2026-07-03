import Testing
@testable import BrowseCraft

// 中文注释：阅读页解析回归测试，确认章节元数据和正文图片 URL 仍按旧规则解析。
struct SwiftSoupReaderParserTests {
    @Test func builtInReaderRuleParsesChapterPages() throws {
        let source: Source = BuiltInSource.primaryBuiltIn()
        let parser: SwiftSoupRuleParser = SwiftSoupRuleParser(
            urlResolver: URLResolvingService()
        )

        let chapter: ReaderChapter = try parser.parseReader(
            html: BuiltInRuleHTMLFixtures.readerHTML,
            source: source,
            pageURL: "https://example.test/cn/chapters/735147"
        )

        // 中文注释：阅读页解析要同时保留面包屑、上下章导航和正文图片，支持继续阅读和返回目录。
        #expect(chapter.comicTitle == "哥布林殺手")
        #expect(chapter.chapterTitle == "第83話")
        #expect(chapter.catalogURL == "https://example.test/cn/comics/20515")
        #expect(chapter.previousChapterURL == "https://example.test/cn/chapters/727041")
        #expect(chapter.nextChapterURL == "https://example.test/cn/chapters/735148")
        // 中文注释：图片 URL 应优先读取真实 data-src，不能把 lazy-load placeholder 当成页面图。
        #expect(chapter.pageImageURLs.count == 3)
        #expect(chapter.pageImageURLs[0] == "https://image.example/chapters/735147/1-95aef5.jpg")
        #expect(chapter.pageImageURLs[2] == "https://image.example/chapters/735147/3-6d79f1.jpg")
    }
}
