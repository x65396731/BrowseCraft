import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime
import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：规则的 `ready` 字段 → `PageLoadRequest.readinessSelector` 这一段接线的合同。
// 用记录型页面加载器截住请求，不碰 WebView；三种输入：声明了 CSS ready、未声明、声明了 XPath。
struct ComicListReadinessSelectorWiringTests {
    @Test func cssReadyRuleReachesThePageLoadRequest() async throws {
        let recorder: RecordingPageLoader = RecordingPageLoader()
        let loader: ComicSourceListLoader = Self.listLoader(recorder)
        _ = try await loader.executeWithPagination(source: Self.source(ready: ExtractRule(selector: ".card", function: .raw)), page: 1)

        let request: PageLoadRequest = try #require(recorder.requests.first)
        #expect(request.readinessSelector == ".card")
    }

    @Test func missingReadyRuleLeavesTheRequestWithoutASelector() async throws {
        let recorder: RecordingPageLoader = RecordingPageLoader()
        let loader: ComicSourceListLoader = Self.listLoader(recorder)
        _ = try await loader.executeWithPagination(source: Self.source(ready: nil), page: 1)

        let request: PageLoadRequest = try #require(recorder.requests.first)
        #expect(request.readinessSelector == nil)
    }

    /// 中文注释:漫画 V2 严格校验在更上游就拒绝 xpath(`comic-v2-extract-xpath-*`),非 CSS 这一档到不了接线层,
    /// 由 Runtime 的 ReadinessSelectorTests 单独覆盖。这里覆盖校验放行、但当前节点标记对整页无意义的一档。
    @Test func currentNodeMarkerReadyRuleIsNotForwarded() async throws {
        let recorder: RecordingPageLoader = RecordingPageLoader()
        let loader: ComicSourceListLoader = Self.listLoader(recorder)
        _ = try await loader.executeWithPagination(
            source: Self.source(ready: ExtractRule(selector: "this", function: .raw)),
            page: 1
        )

        let request: PageLoadRequest = try #require(recorder.requests.first)
        #expect(request.readinessSelector == nil)
    }

    // MARK: - 夹具

    private static func listLoader(_ pageContentLoader: PageContentLoader) -> ComicSourceListLoader {
        return ComicSourceListLoader(
            pageContentLoader: pageContentLoader,
            comicRuleParser: CoreComicRuleSourceParser(),
            urlResolver: URLResolvingService()
        )
    }

    private static func source(ready: ExtractRule?) -> Source {
        let rule: SiteRule = SiteRule(
            version: 1,
            site: nil,
            urlPatterns: nil,
            pages: nil,
            ruleSets: nil,
            sharedRequest: nil,
            flags: nil,
            name: "Ready Source",
            baseUrl: "https://comic.test",
            list: ListRule(
                id: "all",
                url: "https://comic.test/list.html",
                item: ".card",
                title: ".title a",
                link: ".title a@href",
                cover: nil,
                type: .comic,
                latestText: nil,
                pagination: nil,
                ready: ready,
                request: RequestConfig(needsWebView: true)
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
            id: "ready-source",
            name: "Ready Source",
            baseURL: "https://comic.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

/// 中文注释：记录收到的 PageLoadRequest，返回一份能解析出条目的固定 HTML。
private final class RecordingPageLoader: PageContentLoader, @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var recorded: [PageLoadRequest] = []

    var requests: [PageLoadRequest] {
        return self.lock.withLock { self.recorded }
    }

    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        self.lock.withLock { self.recorded.append(request) }
        let body: String = """
        <html><body>
          <div class="card"><div class="title"><a href="/comic/1.html">作品一</a></div></div>
        </body></html>
        """
        return PageContentResponse(content: body, finalURL: request.url)
    }
}
