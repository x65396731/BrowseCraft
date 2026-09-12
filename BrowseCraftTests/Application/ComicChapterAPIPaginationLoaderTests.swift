import Foundation
import Testing
@testable import BrowseCraft
import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime

/// 中文注释：`BC-COMIC-028` App 侧翻页循环的合同用例。
///
/// 钉住四件事：**不声明分页的规则一次请求都不多发**（行为逐字不变）、翻页时**表单体也在变**
/// （manmanapp 的页码占位串落在 body 上，只替换 URL 会让每页拿回同一份数据、循环空转到
/// `maxPages`）、分页 body 里的其它占位串仍走模板解析、以及**空页即停 / `maxPages` 硬止损 / 按 URL 去重**。
struct ComicChapterAPIPaginationLoaderTests {
    // MARK: - 不声明分页：逐字不变

    @Test func ruleWithoutPaginationIssuesExactlyOneRequest() async throws {
        let loader: PagedChapterAPIStub = PagedChapterAPIStub(
            pages: ["1": Self.page(["第01话"], startingAt: 1)]
        )
        let sut: ComicSourceDetailLoader = ComicSourceDetailLoader(
            pageContentLoader: loader,
            comicRuleParser: CoreComicRuleSourceParser()
        )

        let content: ComicRuleParsedDetail = try await sut.execute(
            source: Self.source(
                url: "https://example.test/api/chapters?page=1",
                bodyValue: "id={detailSlug}",
                pagination: nil
            ),
            item: Self.item()
        )

        #expect(loader.requestedURLs == ["https://example.test/api/chapters?page=1"])
        #expect(loader.requestBodies == ["id=7"])
        #expect(content.chapters.map(\.title) == ["第01话"])
    }

    // MARK: - `item.idCode`：漫画按作品参数化的唯一出路

    /// 中文注释：`chapterAPI` 是**整个 source 共用**的一条规则，App 对每一部作品都用它。
    /// 站点接口要的作品号因此只能写成模板令牌，由运行期按当前作品替换。
    ///
    /// Core 的 V2 校验器拒收 `detailSlug`/`comicId` 这类按 URL 形状推断的令牌
    /// （`template-implicit-inference`），并在报错文案里指名要用 `item.idCode`——
    /// 所以它是漫画这条路上唯一可用的令牌。而漫画侧的模板解析器此前**没有这个 case**
    /// （影视侧有），未命中的令牌被替换成空串，规则会发出 `id=`，拿回空目录。
    @Test func idCodeTokenResolvesFromTheItem() async throws {
        let loader: PagedChapterAPIStub = PagedChapterAPIStub(
            pages: ["1": Self.page(["第01话"], startingAt: 1)]
        )
        let sut: ComicSourceDetailLoader = ComicSourceDetailLoader(
            pageContentLoader: loader,
            comicRuleParser: CoreComicRuleSourceParser()
        )

        _ = try await sut.execute(
            source: Self.source(
                url: "https://example.test/api/chapters?page=1",
                bodyValue: "id={item.idCode}",
                pagination: nil
            ),
            item: Self.item(idCode: "1221036")
        )

        #expect(loader.requestBodies == ["id=1221036"])
    }

    /// 中文注释：取不到 idCode 时回落成空串——与其它未命中令牌同一行为，不特殊。
    /// 钉住它是为了说明「发出 `id=`」是**可观察的失败形态**，而不是悄悄换个值。
    @Test func idCodeTokenFallsBackToEmptyWhenAbsent() async throws {
        let loader: PagedChapterAPIStub = PagedChapterAPIStub(
            pages: ["1": Self.page(["第01话"], startingAt: 1)]
        )
        let sut: ComicSourceDetailLoader = ComicSourceDetailLoader(
            pageContentLoader: loader,
            comicRuleParser: CoreComicRuleSourceParser()
        )

        _ = try await sut.execute(
            source: Self.source(
                url: "https://example.test/api/chapters?page=1",
                bodyValue: "id={item.idCode}",
                pagination: nil
            ),
            item: Self.item()
        )

        #expect(loader.requestBodies == ["id="])
    }

    // MARK: - 占位串在 URL 上

    @Test func paginationWalksPagesUntilAnEmptyOne() async throws {
        let loader: PagedChapterAPIStub = PagedChapterAPIStub(
            pages: [
                "1": Self.page(["第01话", "第02话"], startingAt: 1),
                "2": Self.page(["第03话"], startingAt: 3),
                "3": Self.page([], startingAt: 0)
            ]
        )
        let sut: ComicSourceDetailLoader = ComicSourceDetailLoader(
            pageContentLoader: loader,
            comicRuleParser: CoreComicRuleSourceParser()
        )

        let content: ComicRuleParsedDetail = try await sut.execute(
            source: Self.urlPagedSource(),
            item: Self.item()
        )

        #expect(loader.requestedURLs == [
            "https://example.test/api/chapters?page=1",
            "https://example.test/api/chapters?page=2",
            "https://example.test/api/chapters?page=3"
        ])
        #expect(content.chapters.map(\.title) == ["第01话", "第02话", "第03话"])
    }

    /// 中文注释：同一话在相邻页重复出现是分页接口的常见行为，聚合按 URL 去重。
    @Test func duplicatesAcrossPagesAreDropped() async throws {
        let loader: PagedChapterAPIStub = PagedChapterAPIStub(
            pages: [
                "1": Self.page(["第01话", "第02话"], startingAt: 1),
                "2": Self.page(["第02话", "第03话"], startingAt: 2),
                "3": Self.page([], startingAt: 0)
            ]
        )
        let sut: ComicSourceDetailLoader = ComicSourceDetailLoader(
            pageContentLoader: loader,
            comicRuleParser: CoreComicRuleSourceParser()
        )

        let content: ComicRuleParsedDetail = try await sut.execute(
            source: Self.urlPagedSource(),
            item: Self.item()
        )

        #expect(content.chapters.map(\.url) == [
            "https://example.test/c/1",
            "https://example.test/c/2",
            "https://example.test/c/3"
        ])
    }

    /// 中文注释：`maxPages` 是这条规则唯一的硬止损——站点一直回内容也必须停。
    @Test func maxPagesStopsAnEndlessSource() async throws {
        let loader: PagedChapterAPIStub = PagedChapterAPIStub(
            pages: [
                "1": Self.page(["第01话"], startingAt: 1),
                "2": Self.page(["第02话"], startingAt: 2),
                "3": Self.page(["第03话"], startingAt: 3)
            ]
        )
        let sut: ComicSourceDetailLoader = ComicSourceDetailLoader(
            pageContentLoader: loader,
            comicRuleParser: CoreComicRuleSourceParser()
        )

        let content: ComicRuleParsedDetail = try await sut.execute(
            source: Self.urlPagedSource(maxPages: 2),
            item: Self.item()
        )

        #expect(loader.requestedURLs.count == 2)
        #expect(content.chapters.map(\.title) == ["第01话", "第02话"])
    }

    // MARK: - 占位串在表单体上（manmanapp 形状）

    /// 中文注释：URL 恒定、页码只在 body 里。若只替换 URL，三页会拿回同一份数据，
    /// 章节数不会增长而请求会一直打到 `maxPages`——这条用例正是钉这件事。
    @Test func formBodyIsRewrittenForEachPage() async throws {
        let loader: PagedChapterAPIStub = PagedChapterAPIStub(
            pages: [
                "1": Self.page(["第01话"], startingAt: 1),
                "2": Self.page(["第02话"], startingAt: 2),
                "3": Self.page([], startingAt: 0)
            ]
        )
        let sut: ComicSourceDetailLoader = ComicSourceDetailLoader(
            pageContentLoader: loader,
            comicRuleParser: CoreComicRuleSourceParser()
        )

        let content: ComicRuleParsedDetail = try await sut.execute(
            source: Self.bodyPagedSource(),
            item: Self.item()
        )

        #expect(loader.requestedURLs == Array(
            repeating: "https://example.test/api/chapters",
            count: 3
        ))
        #expect(loader.requestBodies == ["id=7&sort=0&page=1", "id=7&sort=0&page=2", "id=7&sort=0&page=3"])
        #expect(content.chapters.map(\.title) == ["第01话", "第02话"])
    }

    /// 中文注释：分页 body 里的 `{detailSlug}` 仍要解析。规划器只认页码占位串，
    /// 把它的输出整段盖到已解析的请求上会让其它占位串原样发出去。
    @Test func paginatedBodyStillResolvesOtherTemplateTokens() async throws {
        let loader: PagedChapterAPIStub = PagedChapterAPIStub(
            pages: [
                "1": Self.page(["第01话"], startingAt: 1),
                "2": Self.page([], startingAt: 0)
            ]
        )
        let sut: ComicSourceDetailLoader = ComicSourceDetailLoader(
            pageContentLoader: loader,
            comicRuleParser: CoreComicRuleSourceParser()
        )

        _ = try await sut.execute(source: Self.bodyPagedSource(), item: Self.item())

        #expect(loader.requestBodies.allSatisfy { $0.hasPrefix("id=7&") })
    }

    // MARK: - 越界页把已聚合的目录一起丢掉（manmanapp 真实形状）

    /// 中文注释：**越界页不是合同违规，是翻到头了。**
    ///
    /// 2026-09-12 真机实测：manmanapp 的 `works/comic-list-ajax.html` 在越界页回
    /// `{"code":0}`——`data` 键**整个不存在**（10 字节）。解析层按 `itemPath` 判为 `missing`
    /// 并抛合同错，这个错此前会冲出翻页循环，把**已经聚合好的前几页连同整次详情加载一起丢掉**，
    /// 详情页因此显示「0 Chapters」。
    ///
    /// 本用例的三份响应都是从站点真取回来的字节：页 1 / 页 2 的 `id` 与 `title` 逐字取自
    /// `id=1221036&page=1|2`（只去掉规则不读的 `cover_image_url` / `publish_time` /
    /// `likes` / `is_read` 四个字段），越界页则是原样的 `{"code":0}`。
    @Test func outOfRangePageWithoutDataKeyEndsPaginationAndKeepsAggregated() async throws {
        let loader: PagedChapterAPIStub = PagedChapterAPIStub(
            pages: [
                "1": Self.manmanPage(Self.realPageOne),
                "2": Self.manmanPage(Self.realPageTwo),
                "3": Self.realOutOfRangePayload
            ]
        )
        let sut: ComicSourceDetailLoader = ComicSourceDetailLoader(
            pageContentLoader: loader,
            comicRuleParser: CoreComicRuleSourceParser()
        )

        let content: ComicRuleParsedDetail = try await sut.execute(
            source: Self.manmanSource(),
            item: Self.item(idCode: "1221036")
        )

        #expect(content.chapters.count == 20)
        #expect(content.chapters.first?.title == "完结篇 吻")
        #expect(content.chapters.first?.url == "https://manmanapp.com/comic/detail-1439783.html")
        #expect(content.chapters.last?.title == "第154话 好人有好报")
        #expect(loader.requestBodies == [
            "id=1221036&page=1",
            "id=1221036&page=2",
            "id=1221036&page=3"
        ])
    }

    /// 中文注释：**第一页就抛合同错仍然是真错误**——那说明规则本身不对，不是翻到头了。
    /// 这一条守住 `iteration > 0` 那一格：越界判定不能把「这条规则从来就取不到章节」
    /// 吞成一份空目录。
    @Test func contractErrorOnTheFirstPageStillThrows() async throws {
        let loader: PagedChapterAPIStub = PagedChapterAPIStub(
            pages: ["1": Self.realOutOfRangePayload]
        )
        let sut: ComicSourceDetailLoader = ComicSourceDetailLoader(
            pageContentLoader: loader,
            comicRuleParser: CoreComicRuleSourceParser()
        )

        await #expect(throws: (any Error).self) {
            _ = try await sut.execute(
                source: Self.manmanSource(),
                item: Self.item(idCode: "1221036")
            )
        }
    }

    /// 中文注释：**网络类错误不算翻到头**，哪怕已经聚合到过条目也要往上抛。
    /// 把它吞成「到头了」会让用户看到一份被静默截短的目录，却没有任何东西告诉他为什么少了。
    @Test func networkErrorMidPaginationStillThrows() async throws {
        let loader: FailingSecondPageStub = FailingSecondPageStub(
            firstPage: Self.manmanPage(Self.realPageOne)
        )
        let sut: ComicSourceDetailLoader = ComicSourceDetailLoader(
            pageContentLoader: loader,
            comicRuleParser: CoreComicRuleSourceParser()
        )

        await #expect(throws: URLError.self) {
            _ = try await sut.execute(
                source: Self.manmanSource(),
                item: Self.item(idCode: "1221036")
            )
        }
    }

    // MARK: - manmanapp 夹具（字节来自站点真实响应）

    private static let realPageOne: [(String, String)] = [
        ("1439783", "完结篇 吻"),
        ("1439464", "番外篇 关于孩子"),
        ("1439205", "番外篇 爱豆夏与小助理"),
        ("1438741", "番外篇 父母爱情（下）"),
        ("1438234", "番外篇 父母爱情（上）"),
        ("1437407", "第168话 番外×2"),
        ("1437125", "第167话 竹马"),
        ("1436815", "第166话 雄鹰与种子（下）"),
        ("1436480", "第165话 雄鹰与种子（上）"),
        ("1436105", "第164话 没有完结")
    ]

    private static let realPageTwo: [(String, String)] = [
        ("1435701", "第163话 大家的结局"),
        ("1435176", "第162话 想要的幸福"),
        ("1434497", "第161话 送礼物原来很简单"),
        ("1433337", "第160话 我喜欢上你了！"),
        ("1432772", "第159话 真相"),
        ("1432495", "第158话 虚惊"),
        ("1432175", "第157话 再遇"),
        ("1430987", "第156话 夏商的愤怒"),
        ("1430462", "第155话 逃脱与救援"),
        ("1430021", "第154话 好人有好报")
    ]

    /// 中文注释：越界页的原文，10 字节，`data` 键不存在——这一串就是整条缺陷的源头。
    private static let realOutOfRangePayload: String = #"{"code":0}"#

    private static func manmanPage(_ chapters: [(String, String)]) -> String {
        let items: [String] = chapters.map { id, title in
            return #"{"id":"\#(id)","title":"\#(title)"}"#
        }
        return #"{"code":0,"data":[\#(items.joined(separator: ","))]}"#
    }

    /// 中文注释：逐项照抄 2026-09-11 发布的那份规则的 `detail.chapterAPI`
    /// （`prototype-output-bc058-20260911`）：页码占位串在表单体上、章节地址由
    /// `urlTemplate` 拼、响应按 `transportOnly` 判。
    private static func manmanSource(maxPages: Int = 200) -> Source {
        let chapterAPI: DetailChapterAPIRule = DetailChapterAPIRule(
            url: "https://manmanapp.com/works/comic-list-ajax.html",
            request: RequestConfig(
                method: .post,
                headers: [
                    "Accept": "application/json, text/javascript, */*; q=0.01",
                    "Content-Type": "application/x-www-form-urlencoded",
                    "Referer": "{item.detailURL}",
                    "X-Requested-With": "XMLHttpRequest"
                ],
                body: RequestBody(
                    contentType: "application/x-www-form-urlencoded",
                    value: "id={item.idCode}&page={page}"
                )
            ),
            itemPath: "data[]",
            titlePath: "title",
            urlTemplate: "https://manmanapp.com/comic/detail-{id}.html",
            preferAPI: true,
            responsePolicy: APIResponsePolicy(mode: .transportOnly),
            pagination: ChapterAPIPaginationRule(
                pageToken: "{page}",
                start: 1,
                stopWhen: ChapterAPIPaginationStopCondition.emptyItems,
                count: nil,
                maxPages: maxPages
            )
        )
        return Self.source(chapterAPI: chapterAPI)
    }

    // MARK: - 夹具

    private static func urlPagedSource(maxPages: Int = 5) -> Source {
        return Self.source(
            url: "https://example.test/api/chapters?page={page}",
            bodyValue: "id={detailSlug}",
            pagination: Self.pagination(maxPages: maxPages)
        )
    }

    private static func bodyPagedSource(maxPages: Int = 5) -> Source {
        return Self.source(
            url: "https://example.test/api/chapters",
            bodyValue: "id={detailSlug}&sort=0&page={page}",
            pagination: Self.pagination(maxPages: maxPages)
        )
    }

    private static func pagination(maxPages: Int) -> ChapterAPIPaginationRule {
        return ChapterAPIPaginationRule(
            pageToken: "{page}",
            start: 1,
            stopWhen: ChapterAPIPaginationStopCondition.emptyItems,
            count: nil,
            maxPages: maxPages
        )
    }

    private static func page(_ titles: [String], startingAt first: Int) -> String {
        let items: [String] = titles.enumerated().map { offset, title in
            return "{\"title\":\"\(title)\",\"url\":\"/c/\(first + offset)\"}"
        }
        return "{\"chapters\":[\(items.joined(separator: ","))]}"
    }

    private static func item(idCode: String? = nil) -> ContentItem {
        return ContentItem(
            id: "comic-7",
            idCode: idCode,
            sourceId: "paged-api-source",
            title: "分页目录",
            detailURL: "https://example.test/comic/7",
            coverURL: nil,
            type: .comic,
            latestText: nil
        )
    }

    private static func source(
        url: String,
        bodyValue: String,
        pagination: ChapterAPIPaginationRule?
    ) -> Source {
        let chapterAPI: DetailChapterAPIRule = DetailChapterAPIRule(
            url: url,
            request: RequestConfig(
                method: .post,
                headers: ["Accept": "application/json"],
                body: RequestBody(
                    contentType: "application/x-www-form-urlencoded",
                    value: bodyValue
                )
            ),
            itemPath: "chapters[]",
            titlePath: "title",
            urlPath: "url",
            preferAPI: true,
            pagination: pagination
        )
        return Self.source(chapterAPI: chapterAPI)
    }

    private static func source(chapterAPI: DetailChapterAPIRule) -> Source {
        let rule: SiteRule = SiteRule(
            version: 1,
            site: nil,
            urlPatterns: nil,
            pages: nil,
            ruleSets: nil,
            sharedRequest: nil,
            flags: nil,
            name: "Paged API Source",
            baseUrl: "https://example.test",
            list: ListRule(
                id: "updates",
                url: "https://example.test/updates",
                item: ".item",
                title: "a",
                link: "a@href",
                cover: nil,
                type: .comic,
                latestText: nil
            ),
            listTabs: nil,
            detail: DetailRule(
                id: "detail",
                chapterAPI: chapterAPI,
                chapterItem: ".chapter a",
                chapterTitle: "this",
                chapterLink: "this@href"
            ),
            gallery: GalleryRule(
                id: "reader",
                imageItem: "img",
                imageUrl: "this@src"
            ),
            video: nil
        )

        return Source(
            id: "paged-api-source",
            name: "Paged API Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

/// 中文注释：按页码回不同页——页码先看 URL 的 `page` 查询参数，取不到再看表单体里的
/// `page=N`。两种占位串位置共用一个桩，正是为了让「只替换 URL」的实现在 body 分页上露馅。
private final class PagedChapterAPIStub: PageContentLoader, @unchecked Sendable {
    private enum LoaderError: LocalizedError {
        case missingPage(String)

        var errorDescription: String? {
            switch self {
            case .missingPage(let key):
                return "夹具没有为第 \(key) 页准备响应"
            }
        }
    }

    private let pages: [String: String]
    private(set) var requestedURLs: [String] = []
    private(set) var requestBodies: [String] = []

    init(pages: [String: String]) {
        self.pages = pages
    }

    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        self.requestedURLs.append(request.url.absoluteString)
        let body: String? = request.requestConfig?.body?.value
        if let body: String {
            self.requestBodies.append(body)
        }

        let key: String = Self.pageNumber(url: request.url, body: body) ?? "1"
        guard let payload: String = self.pages[key] else {
            throw LoaderError.missingPage(key)
        }
        return PageContentResponse(content: payload, finalURL: request.url)
    }

    private static func pageNumber(url: URL, body: String?) -> String? {
        if let query: String = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "page" })?
            .value {
            return query
        }
        guard let body: String else {
            return nil
        }
        return body
            .split(separator: "&")
            .first { $0.hasPrefix("page=") }
            .map { String($0.dropFirst("page=".count)) }
    }
}

/// 中文注释：第一页正常回内容，第二页抛网络错——用来钉「非合同类错误不算翻到头」。
/// 不复用 `PagedChapterAPIStub` 的「夹具缺页」错误，是因为那个错的语义是夹具没写全，
/// 与「站点断线」不是一回事，混用会让这条用例证明不了它要证的事。
private final class FailingSecondPageStub: PageContentLoader, @unchecked Sendable {
    private let firstPage: String
    private(set) var requestCount: Int = 0

    init(firstPage: String) {
        self.firstPage = firstPage
    }

    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        self.requestCount += 1
        if self.requestCount == 1 {
            return PageContentResponse(content: self.firstPage, finalURL: request.url)
        }
        throw URLError(.networkConnectionLost)
    }
}
