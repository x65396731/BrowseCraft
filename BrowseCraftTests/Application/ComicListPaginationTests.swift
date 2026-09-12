import Foundation
import Testing
@testable import BrowseCraft
import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime

/// 中文注释：漫画**列表**的翻页。
///
/// 2026-09-12 真机报「没分页」倒查出来的：规则里 `list.url` 带着 `{page}`、
/// `listRules[0].pagination` 也声明了 `{pagePlaceholder, stopWhenEmpty, urlTemplate}`，
/// 第 1 页也确实是用 `category_1.html` 取的——但 App 判 `nextPage=nil`，永远停在第 1 页。
///
/// 成因是 Runtime 的一处缺口：`ComicSourceRuntime.loadList` 根本不传 `pagination`，
/// 而 `ComicSourceListLoader.execute` 的返回类型是 `[ContentItem]`，连产出它的位置都没有。
/// **漫画的「搜索」有分页，「列表」没有**；影视侧两者都有。
struct ComicListPaginationTests {
    @Test func listAdvancesToTheNextPage() async throws {
        let loader: PagedListStub = PagedListStub()
        let sut: ComicSourceListLoader = Self.listLoader(loader)

        let result = try await sut.executeWithPagination(
            source: Self.source(),
            page: 1
        )

        #expect(result.items.map(\.title) == ["作品一", "作品二"])
        #expect(result.pagination?.nextPage == 2)
        #expect(result.pagination?.nextURL == "https://comic.test/category_2.html")
        #expect(result.pagination?.source == .pagePlaceholder)
    }

    @Test func ruleWithoutPaginationYieldsNoNextPage() async throws {
        """
        中文注释：不声明分页的规则行为逐字不变——这是本改动的边界守卫。
        """

        let loader: PagedListStub = PagedListStub()
        let sut: ComicSourceListLoader = Self.listLoader(loader)

        let result = try await sut.executeWithPagination(
            source: Self.source(pagination: nil),
            page: 1
        )

        #expect(result.items.isEmpty == false)
        #expect(result.pagination == nil)
    }

    /// 中文注释：**翻过末页是「到头了」，不是「规则坏了」。**
    ///
    /// 2026-09-12 实测：manmanapp `category_999.html` 与 dongmanhi `…/999.html`
    /// 越界页都回 HTTP 200 + 0 条。此前列表加载器一律抛 `selectorEmpty`，
    /// 用户滑到底看到的是报错。判据按第几页分、不按内容分——与 `BC-COMIC-119`
    /// 在章节分页上定的那条同形。
    @Test func emptyPageBeyondTheFirstEndsTheList() async throws {
        let loader: PagedListStub = PagedListStub(emptyPages: [2])
        let sut: ComicSourceListLoader = Self.listLoader(loader)

        let result = try await sut.executeWithPagination(
            source: Self.source(),
            page: 2
        )

        #expect(result.items.isEmpty)
        #expect(result.pagination?.nextPage == nil)
    }

    /// 第 1 页零条目仍然是真错误——那说明规则不对，不能吞成一份空列表。
    @Test func emptyFirstPageIsStillAnError() async throws {
        let loader: PagedListStub = PagedListStub(emptyPages: [1])
        let sut: ComicSourceListLoader = Self.listLoader(loader)

        await #expect(throws: (any Error).self) {
            _ = try await sut.executeWithPagination(source: Self.source(), page: 1)
        }
    }

    @Test func maxPagesIsTheHardStop() async throws {
        let loader: PagedListStub = PagedListStub()
        let sut: ComicSourceListLoader = Self.listLoader(loader)

        let result = try await sut.executeWithPagination(
            source: Self.source(maxPages: 2),
            page: 2
        )

        #expect(result.items.isEmpty == false)
        #expect(result.pagination?.nextPage == nil, "到达 maxPages 就不得再给下一页")
    }

    // MARK: - 夹具

    private static func listLoader(_ pageContentLoader: PageContentLoader) -> ComicSourceListLoader {
        return ComicSourceListLoader(
            pageContentLoader: pageContentLoader,
            comicRuleParser: CoreComicRuleSourceParser(),
            urlResolver: URLResolvingService()
        )
    }

    /// manmanapp 的形状：列表地址自带 `{page}`，分页合同声明占位串与空页终止。
    private static func source(
        pagination: PaginationRule? = PaginationRule(
            pagePlaceholder: "{page}",
            stopWhenEmpty: true
        ),
        maxPages: Int? = nil
    ) -> Source {
        let rule: SiteRule = SiteRule(
            version: 1,
            site: nil,
            urlPatterns: nil,
            pages: nil,
            ruleSets: nil,
            sharedRequest: nil,
            flags: nil,
            name: "Paged List Source",
            baseUrl: "https://comic.test",
            list: ListRule(
                id: "all",
                url: "https://comic.test/category_{page}.html",
                item: ".card",
                title: ".title a",
                link: ".title a@href",
                cover: nil,
                type: .comic,
                latestText: nil,
                pagination: maxPages.map { value in
                    PaginationRule(
                        pagePlaceholder: "{page}",
                        maxPages: value,
                        stopWhenEmpty: true
                    )
                } ?? pagination
            ),
            listTabs: nil,
            detail: DetailRule(
                id: "detail",
                chapterItem: ".chapter a",
                chapterTitle: "this",
                chapterLink: "this@href"
            ),
            gallery: GalleryRule(id: "reader", imageItem: "img", imageUrl: "this@src"),
            video: nil
        )
        return Source(
            id: "paged-list-source",
            name: "Paged List Source",
            baseURL: "https://comic.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

/// 中文注释：按 URL 里的页码回不同页；`emptyPages` 里的页码回空列表。
private final class PagedListStub: PageContentLoader, @unchecked Sendable {
    private let emptyPages: Set<Int>
    private(set) var requestedURLs: [String] = []

    init(emptyPages: Set<Int> = []) {
        self.emptyPages = emptyPages
    }

    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        self.requestedURLs.append(request.url.absoluteString)
        let page: Int = Self.pageNumber(request.url) ?? 1
        if self.emptyPages.contains(page) {
            return PageContentResponse(content: "<html><body></body></html>", finalURL: request.url)
        }
        let body: String = """
        <html><body>
          <div class="card"><div class="title"><a href="/comic/1.html">作品一</a></div></div>
          <div class="card"><div class="title"><a href="/comic/2.html">作品二</a></div></div>
        </body></html>
        """
        return PageContentResponse(content: body, finalURL: request.url)
    }

    private static func pageNumber(_ url: URL) -> Int? {
        guard let match = url.absoluteString.range(of: #"category_(\d+)\.html"#, options: .regularExpression) else {
            return nil
        }
        return Int(url.absoluteString[match].dropFirst("category_".count).dropLast(".html".count))
    }
}
