import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime
import Foundation
import ReadiumShared
import ReadiumNavigator
import Testing
@testable import BrowseCraft

// 中文注释：站点书从 catalog 到出版物的整链固定输入：真实 catalog → Source → BookSourceRuntime（网页由夹具桩）
// → 详情 / 章节 / 正文或音频 → manifest → Readium Publication。两站各一条。

struct BookSourceRuntimeEndToEndTests {
    @Test func biquhuaTextBookFlowsFromListToPublication() async throws {
        let loader: FixturePageContentLoader = FixturePageContentLoader(fixtures: [
            "https://www.biquhua.com/top/all_0_1.html": "biquhua-list-p1",
            "https://www.biquhua.com/book/0/110/": "biquhua-detail-110",
            "https://www.biquhua.com/book/0/110/129023.html": "biquhua-reader-110-129023",
        ])
        let source: Source = try BookRuntimeFixtures.source(fixture: "biquhua-catalog")
        let runtime: BookSourceRuntime = try BookSourceRuntimeFactory(pageContentLoader: loader).makeRuntime(source: source)
        let context: SourceRuntimeContext = BookRuntimeFixtures.context(sourceID: source.id)

        #expect(runtime.capabilities.supportsDetail)
        #expect(runtime.capabilities.supportsReader == false)
        #expect(runtime.capabilities.supportsPagination == false)
        #expect(runtime.capabilities.requiresAccount, "biquhua 有 loginURL")

        let list: SourceListOutput = try await runtime.loadList(SourceListInput(page: 1, urlOverride: nil, context: context))
        #expect(list.items.count == 30)
        #expect(list.pagination == nil)
        #expect(list.items.first?.itemReference?.contentType == .article)

        let detail: SourceDetailOutput = try await runtime.loadDetail(
            SourceDetailInput(detailURL: URL(string: "https://www.biquhua.com/book/0/110/")!, context: context, itemReference: nil)
        )
        #expect(detail.metadata?.title == "普罗之主")
        #expect(detail.chapters.count == 112)

        let chapterURL: URL = URL(string: "https://www.biquhua.com/book/0/110/129023.html")!
        let content: SourceBookContentOutput = try await runtime.loadBookContent(SourceBookContentInput(chapterURL: chapterURL, context: context))
        guard case .text(_, let paragraphs) = content.content else {
            Issue.record("expected text content")
            return
        }
        #expect(paragraphs.count >= 12)

        let loaded: LoadedBookPublication = try await LoadBookPublicationUseCase(runtimeResolver: SingleRuntimeResolver(runtime: runtime))
            .execute(source: source, detailURL: URL(string: "https://www.biquhua.com/book/0/110/")!)
        #expect(loaded.manifest.title == "普罗之主")
        #expect(loaded.manifest.items.count == 112)
        #expect(loaded.manifest.items.first?.href == "chapters/0001.xhtml")
        #expect(loaded.manifest.isAudiobook == false)

        let publication: Publication = ReadiumSitePublicationBuilder().build(manifest: loaded.manifest, contentProvider: loaded.contentProvider)
        #expect(publication.readingOrder.count == 112)
        #expect(publication.metadata.title == "普罗之主")
        // 中文注释：每章一个 position——没有它 Readium 预加载按 0 计数，打开一章就把全书逐章取页（2026-09-14 sfacg 真机）。
        let positions: [[Locator]] = try await publication.positionsByReadingOrder().get()
        #expect(positions.count == 112)
        #expect(positions.allSatisfy { $0.count == 1 })
        #expect(positions.last?.first?.locations.position == 112)
        #expect(positions.first?.first?.href == publication.readingOrder.first?.url())
        let firstChapter: Link = try #require(publication.readingOrder.first { $0.title?.isEmpty == false })
        let index: Int = try #require(loaded.manifest.items.firstIndex { $0.chapterURL == chapterURL })
        let resource: Resource = try #require(publication.get(publication.readingOrder[index]))
        let xhtml: String = try await resource.readAsString().get()
        #expect(xhtml.contains("<p>"))
        #expect(xhtml.contains("xmlns=\"http://www.w3.org/1999/xhtml\""))
        #expect(xhtml.contains("<br") == false)
        _ = firstChapter
        #expect(loader.requestedURLs.filter { $0 == chapterURL.absoluteString }.count == 2, "运行时一次 + 出版物按需一次")
    }

    @Test func loyalbooksAudiobookFlowsToAudioPublicationWithoutFetchingMedia() async throws {
        let loader: FixturePageContentLoader = FixturePageContentLoader(fixtures: [
            // 中文注释：第 1 页是页面自己的地址，不代入模板（`?page=1` 会被站点 302 到 http）。
            "https://www.loyalbooks.com/genre/Adventure": "loyalbooks-list-adventure-p1",
            "https://www.loyalbooks.com/book/tom-sawyer-by-mark-twain": "loyalbooks-detail-tom-sawyer",
        ])
        let source: Source = try BookRuntimeFixtures.source(fixture: "loyalbooks-catalog")
        let runtime: BookSourceRuntime = try BookSourceRuntimeFactory(pageContentLoader: loader).makeRuntime(source: source)
        let context: SourceRuntimeContext = BookRuntimeFixtures.context(sourceID: source.id)

        #expect(runtime.capabilities.supportsPagination)
        let list: SourceListOutput = try await runtime.loadList(SourceListInput(page: 1, urlOverride: nil, context: context))
        #expect(list.items.count > 10)
        #expect(list.pagination?.nextPage == 2)
        #expect(list.pagination?.nextPageURL?.absoluteString == "https://www.loyalbooks.com/genre/Adventure?page=2")
        #expect(loader.requestedURLs.first == "https://www.loyalbooks.com/genre/Adventure", "第 1 页用入口地址，不代入模板")

        let detailURL: URL = URL(string: "https://www.loyalbooks.com/book/tom-sawyer-by-mark-twain")!
        let detail: SourceDetailOutput = try await runtime.loadDetail(SourceDetailInput(detailURL: detailURL, context: context, itemReference: nil))
        #expect(detail.chapters.count == 17)

        let firstChapter: URL = try #require(detail.chapters.first?.url)
        let content: SourceBookContentOutput = try await runtime.loadBookContent(SourceBookContentInput(chapterURL: firstChapter, context: context))
        guard case .audio(let items) = content.content else {
            Issue.record("expected audio content")
            return
        }
        #expect(items.count == 1)
        #expect(items.first?.url == firstChapter)
        #expect(items.first?.mediaType == "audio/mpeg")
        #expect(loader.requestedURLs.contains(firstChapter.absoluteString) == false, "BC-BOOK-051：mp3 出边不再取页")

        let loaded: LoadedBookPublication = try await LoadBookPublicationUseCase(runtimeResolver: SingleRuntimeResolver(runtime: runtime))
            .execute(source: source, detailURL: detailURL)
        #expect(loaded.manifest.isAudiobook)
        #expect(loaded.manifest.items.allSatisfy { $0.href.hasSuffix(".mp3") })
        let publication: Publication = ReadiumSitePublicationBuilder().build(manifest: loaded.manifest, contentProvider: loaded.contentProvider)
        #expect(publication.readingOrder.count == 17)
        #expect(publication.readingOrder.first?.mediaType?.isAudio == true)
        #expect(publication.metadata.conformsTo.contains(.audiobook))
        // 中文注释：AudioNavigator 只播 publication.get(link) 给得出资源的 href——远程 mp3 由 HTTPContainer 承接。
        #expect(publication.get(publication.readingOrder[0]) != nil)
        let navigator: AudioNavigator = AudioNavigator(publication: publication)
        #expect(navigator.publication.readingOrder.count == 17)
    }

    // 中文注释：BC-BOOK-050：sfacg 作品页只有标题与「点击阅读」，章节在单跳之后的目录页。引擎与 App 都用 iPhone UA，
    // 站点把 `book.sfacg.com/Novel/N/` 302 到移动站 `m.sfacg.com/b/N/`，目录 `/i/N/`、章节 `/c/N/`——夹具就是引擎看到的这套形状。
    // 运行时按 `chapterListURL` 先取作品页（落在移动站）、再取目录页，详情字段与章节都在目录页上解析；正文 `div.yuedu > div` 按 `<p>` 分段。
    @Test func sfacgChaptersLiveOnTheCatalogPageOneHopAfterTheWorkPage() async throws {
        let loader: FixturePageContentLoader = FixturePageContentLoader(
            fixtures: [
                "https://book.sfacg.com/List/": "sfacg-m-list",
                "https://book.sfacg.com/Novel/743628/": "sfacg-m-detail-743628",
                "https://m.sfacg.com/i/743628/": "sfacg-m-catalog-743628",
                "https://m.sfacg.com/c/9077052/": "sfacg-m-reader-9077052",
            ],
            redirects: ["https://book.sfacg.com/Novel/743628/": "https://m.sfacg.com/b/743628/"]
        )
        let source: Source = try BookRuntimeFixtures.source(fixture: "sfacg-catalog")
        let runtime: BookSourceRuntime = try BookSourceRuntimeFactory(pageContentLoader: loader).makeRuntime(source: source)
        let context: SourceRuntimeContext = BookRuntimeFixtures.context(sourceID: source.id)

        let list: SourceListOutput = try await runtime.loadList(SourceListInput(page: 1, urlOverride: nil, context: context))
        #expect(list.items.count == 20)
        #expect(list.items.contains { $0.detailURL?.absoluteString == "https://book.sfacg.com/Novel/743628/" })

        let detailURL: URL = URL(string: "https://book.sfacg.com/Novel/743628/")!
        let detail: SourceDetailOutput = try await runtime.loadDetail(SourceDetailInput(detailURL: detailURL, context: context, itemReference: nil))
        #expect(detail.metadata?.title?.contains("非实然档案：现代魔法") == true)
        #expect(detail.chapters.count == 415)
        #expect(detail.chapters.first?.url.absoluteString == "https://m.sfacg.com/c/9077052/")
        #expect(Array(loader.requestedURLs.dropFirst()) == [
            "https://book.sfacg.com/Novel/743628/",
            "https://m.sfacg.com/i/743628/",
        ], "取页序列：作品页（302 到移动站）→ 目录页（相对落点解析）")

        let chapterURL: URL = try #require(detail.chapters.first?.url)
        let content: SourceBookContentOutput = try await runtime.loadBookContent(SourceBookContentInput(chapterURL: chapterURL, context: context))
        guard case .text(_, let paragraphs) = content.content else {
            Issue.record("expected text content")
            return
        }
        #expect(paragraphs.count >= 100)

        let loaded: LoadedBookPublication = try await LoadBookPublicationUseCase(runtimeResolver: SingleRuntimeResolver(runtime: runtime))
            .execute(source: source, detailURL: detailURL)
        #expect(loaded.manifest.items.count == 415)
    }

    @Test func xhtmlRendererEscapesAndSkipsEmptyParagraphs() {
        let xhtml: String = BookXHTMLRenderer().render(title: "A <b> & \"c\"", paragraphs: ["one", "", "<two>"], language: "zh-Hans")
        #expect(xhtml.contains("<h1>A &lt;b&gt; &amp; &quot;c&quot;</h1>"))
        #expect(xhtml.contains("<p>one</p>"))
        #expect(xhtml.contains("<p>&lt;two&gt;</p>"))
        #expect(xhtml.contains("<p></p>") == false)
        #expect(xhtml.contains("xml:lang=\"zh-Hans\""))
    }

    // 中文注释：BC-BOOK-036 的两半在 App 侧的固定输入（2026-09-14 biquhua 真机倒查）：
    // ① 章内三页按 content.next 拼成一份；② 末页的 a#next 指向下一章 129024.html，运行时必须停下、不取下一章。
    @Test func biquhuaInChapterPagesAreJoinedAndStopAtNextChapter() async throws {
        let loader: FixturePageContentLoader = FixturePageContentLoader(fixtures: [
            "https://www.biquhua.com/book/0/110/129023.html": "biquhua-reader-110-129023",
            "https://www.biquhua.com/book/0/110/129023_2.html": "biquhua-reader-110-129023-p2",
            "https://www.biquhua.com/book/0/110/129023_3.html": "biquhua-reader-110-129023-p3",
        ])
        let chapterURL: URL = URL(string: "https://www.biquhua.com/book/0/110/129023.html")!

        let plainSource: Source = try BookRuntimeFixtures.source(fixture: "biquhua-catalog")
        let plainRuntime: BookSourceRuntime = try BookSourceRuntimeFactory(pageContentLoader: loader).makeRuntime(source: plainSource)
        let plain: SourceBookContentOutput = try await plainRuntime.loadBookContent(SourceBookContentInput(chapterURL: chapterURL, context: BookRuntimeFixtures.context(sourceID: plainSource.id)))
        guard case .text(_, let singlePageParagraphs) = plain.content else {
            Issue.record("expected text content")
            return
        }
        #expect(loader.requestedURLs == [chapterURL.absoluteString], "没有 content.next 时只取第一页")

        let source: Source = try BookRuntimeFixtures.source(fixture: "biquhua-catalog-next")
        let runtime: BookSourceRuntime = try BookSourceRuntimeFactory(pageContentLoader: loader).makeRuntime(source: source)
        let content: SourceBookContentOutput = try await runtime.loadBookContent(SourceBookContentInput(chapterURL: chapterURL, context: BookRuntimeFixtures.context(sourceID: source.id)))
        guard case .text(_, let paragraphs) = content.content else {
            Issue.record("expected text content")
            return
        }
        #expect(paragraphs.count > singlePageParagraphs.count, "三页拼接后段落数必须多于单页")
        #expect(singlePageParagraphs.contains { $0.contains("第(1/3)页") }, "单页取法保留站点标记（页数对不上，不剔）")
        #expect(paragraphs.contains { $0.contains("页") && $0.contains("/3)") } == false, "三页拼接后页码标记全部剔除")
        #expect(Array(loader.requestedURLs.dropFirst()) == [
            "https://www.biquhua.com/book/0/110/129023.html",
            "https://www.biquhua.com/book/0/110/129023_2.html",
            "https://www.biquhua.com/book/0/110/129023_3.html",
        ], "第三页的 a#next 指向下一章 129024.html，必须停在本章末页")
    }

    @Test func pageMarkersAreStrippedOnlyWhenTheyMatchTheJoinedPages() {
        #expect(BookSourceRuntime.isPageMarker("    第(1/3)页", page: 1, of: 3))
        #expect(BookSourceRuntime.isPageMarker("第（2/3）页", page: 2, of: 3))
        #expect(BookSourceRuntime.isPageMarker("(3/3)", page: 3, of: 3))
        #expect(BookSourceRuntime.isPageMarker("第(1/3)页", page: 2, of: 3) == false, "页序对不上")
        #expect(BookSourceRuntime.isPageMarker("第(1/3)页", page: 1, of: 2) == false, "总页数对不上")
        #expect(BookSourceRuntime.isPageMarker("第(1/3)页 他说。", page: 1, of: 3) == false, "不是整段")
        #expect(BookSourceRuntime.isPageMarker("翻到第(1/3)页", page: 1, of: 3) == false)
        let joined: [String] = BookSourceRuntime.joinedParagraphs(pages: [["第(1/3)页", "甲", "第(1/3)页"], ["第(2/3)页", "乙"], ["丙", "第(3/3)页"]])
        #expect(joined == ["甲", "乙", "丙"])
        #expect(BookSourceRuntime.joinedParagraphs(pages: [["第(1/3)页", "甲"]]) == ["第(1/3)页", "甲"], "只取到一页时页数对不上，保留")
    }

    @Test func inChapterPageGuardOnlyAcceptsSiblingPagesOfTheChapter() {
        let chapter: URL = URL(string: "https://www.biquhua.com/book/0/110/129023.html")!
        #expect(BookSourceRuntime.isInChapterPage(URL(string: "https://www.biquhua.com/book/0/110/129023_2.html")!, chapterURL: chapter))
        #expect(BookSourceRuntime.isInChapterPage(URL(string: "https://www.biquhua.com/book/0/110/129023-3.html")!, chapterURL: chapter))
        #expect(BookSourceRuntime.isInChapterPage(URL(string: "https://www.biquhua.com/book/0/110/129024.html")!, chapterURL: chapter) == false, "下一章")
        #expect(BookSourceRuntime.isInChapterPage(URL(string: "https://www.biquhua.com/book/0/110/")!, chapterURL: chapter) == false, "目录")
        #expect(BookSourceRuntime.isInChapterPage(URL(string: "https://m.biquhua.com/book/0/110/129023_2.html")!, chapterURL: chapter) == false, "别的主机")
        #expect(BookSourceRuntime.isInChapterPage(URL(string: "https://www.biquhua.com/book/0/111/129023_2.html")!, chapterURL: chapter) == false, "别的目录")
        #expect(BookSourceRuntime.isInChapterPage(URL(string: "https://www.biquhua.com/book/0/110/129023_2.php")!, chapterURL: chapter) == false, "扩展名不同")
        #expect(BookSourceRuntime.isInChapterPage(URL(string: "https://www.biquhua.com/book/0/110/129023_1.html")!, chapterURL: chapter) == false, "页码从 2 起")
        let paged: URL = URL(string: "https://www.biquhua.com/book/0/110/129023_2.html")!
        #expect(BookSourceRuntime.isInChapterPage(URL(string: "https://www.biquhua.com/book/0/110/129023_3.html")!, chapterURL: paged), "本章地址自己带页码时按词干算")
        let directoryChapter: URL = URL(string: "https://book.sfacg.com/Novel/784270/1042434/9919505/")!
        #expect(BookSourceRuntime.isInChapterPage(URL(string: "https://book.sfacg.com/Novel/784270/1042434/9919507/")!, chapterURL: directoryChapter) == false, "sfacg 的下一章")
    }
}
