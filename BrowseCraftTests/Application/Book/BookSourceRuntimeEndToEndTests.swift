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
        // 中文注释：展示标题用夹具里的真实列表条目标题——列表带分类前缀，取详情那一边（与 sfacg 方向相反，同一条规则）。
        let itemTitle: String = try #require(list.items.first { $0.detailURL?.absoluteString == "https://www.biquhua.com/book/0/110/" }?.title)
        #expect(itemTitle != "普罗之主", "列表条目标题应带前缀，否则这条断言测不到方向")
        #expect(SiteBookTitle.preferred(itemTitle: itemTitle, detailTitle: loaded.manifest.title) == "普罗之主")
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

    // 中文注释：BC-BOOK-045 的 App 侧：搜索由规则声明（`type="search"` 页 + `searchRules[]`，`listRuleRef` 借列表取法），
    // 关键词按 `keywordEncoding` 编进 `{keyword}`；结果页与列表同构，条目落到站点书详情。夹具是 biquhua 真实搜索结果页（2026-09-15 抓取）。
    @Test func biquhuaSearchIsDeclaredByRuleAndParsesTheResultPage() async throws {
        let loader: FixturePageContentLoader = FixturePageContentLoader(fixtures: [
            "https://www.biquhua.com/search.php?q=%E8%BF%B7%E9%AD%82%E9%98%B5": "biquhua-search-mihunzhen",
        ])
        let source: Source = try BookRuntimeFixtures.source(fixture: "biquhua-catalog-search")
        let runtime: BookSourceRuntime = try BookSourceRuntimeFactory(pageContentLoader: loader).makeRuntime(source: source)
        let context: SourceRuntimeContext = BookRuntimeFixtures.context(sourceID: source.id)

        #expect(runtime.capabilities.supportsSearch)
        #expect(runtime is SourceSearchRuntime)

        let output: SourceListOutput = try await runtime.search(SourceSearchInput(keyword: " 迷魂阵 ", page: 1, urlOverride: nil, context: context))
        #expect(loader.requestedURLs == ["https://www.biquhua.com/search.php?q=%E8%BF%B7%E9%AD%82%E9%98%B5"])
        #expect(output.items.count == 1)
        #expect(output.items.first?.title == "[历史]迷魂阵")
        #expect(output.items.first?.detailURL?.absoluteString == "https://www.biquhua.com/book/130/130817/")
        #expect(output.items.first?.itemReference?.contentType == .article)
        #expect(output.items.first?.itemReference?.listContext?.pageID == "search")
        #expect(output.pagination == nil)

        // 中文注释：搜索页排在 pages[] 里，列表取页仍要落到列表页（不能把搜索页当第一页）。
        let list: SourceListOutput = try await BookSourceRuntimeFactory(
            pageContentLoader: FixturePageContentLoader(fixtures: ["https://www.biquhua.com/top/all_0_1.html": "biquhua-list-p1"])
        ).makeRuntime(source: source).loadList(SourceListInput(page: 1, urlOverride: nil, context: context))
        #expect(list.items.count == 30)

        // 中文注释：没声明搜索的 catalog 仍然不支持搜索。
        let plain: BookSourceRuntime = try BookSourceRuntimeFactory(pageContentLoader: loader).makeRuntime(source: try BookRuntimeFixtures.source(fixture: "biquhua-catalog"))
        #expect(plain.capabilities.supportsSearch == false)
        await #expect(throws: SourceRuntimeError.self) {
            _ = try await plain.search(SourceSearchInput(keyword: "x", page: 1, urlOverride: nil, context: context))
        }
        await #expect(throws: SourceRuntimeError.self) {
            _ = try await runtime.search(SourceSearchInput(keyword: "迷魂阵", page: 2, urlOverride: nil, context: context))
        }
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
        // 中文注释：目录页没有书名元素，详情规则只能取 `<title>`；展示标题落到列表条目的干净书名。
        let itemTitle: String = try #require(list.items.first { $0.detailURL?.absoluteString == "https://book.sfacg.com/Novel/743628/" }?.title)
        let shown: String = SiteBookTitle.preferred(itemTitle: itemTitle, detailTitle: loaded.manifest.title)
        #expect(shown.contains("非实然档案：现代魔法"))
        #expect(shown.contains("目录列表") == false)
        #expect(shown.contains("SF轻小说") == false)
    }

    // 中文注释：正文为空的章节（sfacg 互动小说）渲染说明页，不再只有标题。
    @Test func emptyChapterContentRendersANoticeInsteadOfATitleOnlyPage() async throws {
        let chapterURL: URL = URL(string: "https://m.sfacg.com/c/9555423/")!
        let manifest: BookPublicationManifest = BookPublicationManifest(
            identifier: "sfacg::empty",
            title: "她靠马甲杀回，权贵圈争着喊夫人",
            author: nil,
            language: "zh-Hans",
            coverURL: nil,
            items: [BookPublicationItem(href: "chapters/0001.xhtml", title: "你介意当豪门赘婿吗？", chapterURL: chapterURL, kind: .text)]
        )
        let publication: Publication = ReadiumSitePublicationBuilder().build(manifest: manifest) { url in
            throw SourceRuntimeError.emptyContent(chapterURL: url)
        }
        let resource: Resource = try #require(publication.get(publication.readingOrder[0]))
        let xhtml: String = try await resource.readAsString().get()
        #expect(xhtml.contains("<h1>你介意当豪门赘婿吗？</h1>"))
        #expect(xhtml.contains("<p>\(NSLocalizedString("book_reader_chapter_no_web_content", comment: ""))</p>"))
    }

    @Test func siteBookTitlePrefersTheContainedTitle() {
        // 中文注释：三个书站的实际形状。
        #expect(SiteBookTitle.preferred(itemTitle: "[玄幻]普罗之主", detailTitle: "普罗之主") == "普罗之主")
        #expect(SiteBookTitle.preferred(itemTitle: "大傩", detailTitle: "大傩目录列表 - 小说频道 - SF轻小说") == "大傩")
        #expect(SiteBookTitle.preferred(itemTitle: "The Adventures of Tom Sawyer", detailTitle: "The Adventures of Tom Sawyer") == "The Adventures of Tom Sawyer")
        // 中文注释：互不包含时照旧用详情标题；任一边为空取另一边。
        #expect(SiteBookTitle.preferred(itemTitle: "列表名", detailTitle: "完全不同的名字") == "完全不同的名字")
        #expect(SiteBookTitle.preferred(itemTitle: " 普罗之主 ", detailTitle: nil) == "普罗之主")
        #expect(SiteBookTitle.preferred(itemTitle: "", detailTitle: "普罗之主") == "普罗之主")
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
