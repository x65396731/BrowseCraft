//
//  BrowseCraftTests.swift
//  BrowseCraftTests
//
//  Created by 谢飞 on 2026/07/02.
//

import Foundation
import Testing
@testable import BrowseCraft

struct BrowseCraftTests {

    @Test func builtInListRuleParsesComicCards() throws {
        let source: Source = BuiltInSource.primaryBuiltIn()
        let parser: SwiftSoupRuleParser = SwiftSoupRuleParser(
            urlResolver: URLResolvingService()
        )

        let items: [ContentItem] = try parser.parseList(
            html: Self.builtInListHTML,
            source: source
        )

        #expect(items.count == 2)
        #expect(items[0].title == "猎人游戏W")
        #expect(items[0].detailURL == "https://example.test/cn/comics/55355")
        #expect(items[0].coverURL == "https://image.example/comics/55355-9e7018.jpg")
        #expect(items[0].latestText == "第07话")
        #expect(items[1].title == "1步前进 2步后退")
        #expect(items[1].latestText == "短篇 [完]")
    }

    @Test func builtInReaderRuleParsesChapterPages() throws {
        let source: Source = BuiltInSource.primaryBuiltIn()
        let parser: SwiftSoupRuleParser = SwiftSoupRuleParser(
            urlResolver: URLResolvingService()
        )

        let chapter: ReaderChapter = try parser.parseReader(
            html: Self.builtInReaderHTML,
            source: source,
            pageURL: "https://example.test/cn/chapters/735147"
        )

        #expect(chapter.comicTitle == "哥布林殺手")
        #expect(chapter.chapterTitle == "第83話")
        #expect(chapter.catalogURL == "https://example.test/cn/comics/20515")
        #expect(chapter.previousChapterURL == "https://example.test/cn/chapters/727041")
        #expect(chapter.nextChapterURL == "https://example.test/cn/chapters/735148")
        #expect(chapter.pageImageURLs.count == 3)
        #expect(chapter.pageImageURLs[0] == "https://image.example/chapters/735147/1-95aef5.jpg")
        #expect(chapter.pageImageURLs[2] == "https://image.example/chapters/735147/3-6d79f1.jpg")
    }

    @Test func builtInDetailRuleParsesOnlyScopedChapters() throws {
        let source: Source = BuiltInSource.primaryBuiltIn()
        let parser: SwiftSoupRuleParser = SwiftSoupRuleParser(
            urlResolver: URLResolvingService()
        )

        let chapters: [ChapterLink] = try parser.parseDetailChapters(
            html: Self.builtInDetailHTML,
            source: source,
            pageURL: "https://example.test/cn/comics/55355"
        )

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
            html: Self.builtInDetailHTMLWithoutChapterContainer,
            source: source,
            pageURL: "https://example.test/cn/comics/55355"
        )

        #expect(chapters.isEmpty)
    }

    private static let builtInListHTML: String = """
    <main>
      <a href="https://example.test/cn/comics/55355">
        <img src="https://image.example/comics/55355-9e7018.jpg" alt="猎人游戏W">
        <div>第07话</div>
      </a>
      <a href="https://example.test/cn/comics/55354">
        <img data-src="https://image.example/comics/55354-3483fc.jpg" alt="1步前进 2步后退">
        <div>短篇 [完]</div>
      </a>
    </main>
    """

    private static let builtInDetailHTML: String = """
    <main>
      <div data-flux-heading>猎人游戏W</div>
      <aside>
        <a href="https://example.test/cn/chapters/999001">排行第262话</a>
        <a href="https://example.test/cn/chapters/999002">排行第06话</a>
      </aside>
      <div x-data="{ chapters: [{ id: 818145, title: '第02话' }, { id: 818144, title: '第01话' }] }">
        <div class="grid grid-cols-3 gap-4">
          <a href="https://example.test/cn/chapters/818145">第02话</a>
          <a href="https://example.test/cn/chapters/818144">第01话</a>
        </div>
      </div>
    </main>
    """

    private static let builtInDetailHTMLWithoutChapterContainer: String = """
    <main>
      <div data-flux-heading>猎人游戏W</div>
      <aside>
        <a href="https://example.test/cn/chapters/999001">排行第262话</a>
        <a href="https://example.test/cn/chapters/999002">排行第06话</a>
      </aside>
    </main>
    """

    private static let builtInReaderHTML: String = """
    <main>
      <nav>
        <a href="https://example.test/cn/comics/123">随机漫画</a>
      </nav>
      <div data-flux-breadcrumbs-item>
        <a href="https://example.test/cn/comics/20515">哥布林殺手</a>
      </div>
      <div data-flux-breadcrumbs-item>
        <div class="truncate whitespace-nowrap">第83話</div>
      </div>
      <section>
        <img class="page w-full mx-auto" src="https://image.example/chapters/735147/1-95aef5.jpg" alt="哥布林殺手 - 第83話: 第1页">
        <img class="lozad page w-full mx-auto" data-src="https://image.example/chapters/735147/2-77d7bd.jpg" alt="哥布林殺手 - 第83話: 第2页">
        <img class="lozad page w-full mx-auto" data-src="https://image.example/chapters/735147/3-6d79f1.jpg" src="https://placeholder.example/blank.gif" alt="哥布林殺手 - 第83話: 第3页">
      </section>
      <footer>
        <a href="https://example.test/cn/chapters/727041">上一话</a>
        <a href="https://example.test/cn/comics/20515">返回目录</a>
        <a href="https://example.test/cn/chapters/735148">下一话</a>
      </footer>
    </main>
    """

}
