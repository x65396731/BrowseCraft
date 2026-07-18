import Foundation
import Testing
@testable import BrowseCraft

struct ComicRulePageRequestRoutingTests {
    @Test func listAndDetailUseHTTPWhileReaderUsesWebView() async throws {
        let pageContentLoader = RecordingComicRoutePageContentLoader(
            responses: [
                "https://example.test/comics": """
                <article class="item">
                  <a class="title" href="/comic/1">示例漫画</a>
                </article>
                """,
                "https://example.test/comic/1": """
                <main>
                  <h1>示例漫画</h1>
                  <div id="chapters"><a href="/chapter/1">第 1 话</a></div>
                </main>
                """,
                "https://example.test/chapter/1": """
                <main><img class="page" src="/images/1.jpg"></main>
                """
            ]
        )
        let parser = SwiftSoupComicRuleSourceParser(urlResolver: URLResolvingService())
        let source = Self.source()
        let item = ContentItem(
            id: "comic-1",
            sourceId: source.id,
            title: "示例漫画",
            detailURL: "https://example.test/comic/1",
            coverURL: nil,
            type: .comic,
            latestText: "第 1 话"
        )

        _ = try await ComicRuleSourceListLoader(
            pageContentLoader: pageContentLoader,
            comicRuleParser: parser,
            urlResolver: URLResolvingService()
        ).execute(source: source)
        _ = try await ComicRuleSourceDetailLoader(
            pageContentLoader: pageContentLoader,
            comicRuleParser: parser
        ).execute(source: source, item: item)
        _ = try await ComicRuleSourceReaderLoader(
            pageContentLoader: pageContentLoader,
            comicRuleParser: parser
        ).execute(
            source: source,
            item: item,
            chapterURLString: "https://example.test/chapter/1"
        )

        let listRequest = try #require(pageContentLoader.request(for: "https://example.test/comics"))
        let detailRequest = try #require(pageContentLoader.request(for: "https://example.test/comic/1"))
        let readerRequest = try #require(pageContentLoader.request(for: "https://example.test/chapter/1"))

        #expect(listRequest.needsWebView == false)
        #expect(listRequest.autoScroll == false)
        #expect(detailRequest.needsWebView == false)
        #expect(detailRequest.autoScroll == false)
        #expect(readerRequest.needsWebView == true)
        #expect(readerRequest.autoScroll == true)
        #expect(listRequest.headers?["User-Agent"] == "BrowseCraft")
        #expect(detailRequest.headers?["Referer"] == "https://example.test/")
        #expect(readerRequest.cookiePolicy == .browserThenCustom)
    }

    private static func source() -> Source {
        let sharedRequest = RequestConfig(
            scope: .site,
            mergePolicy: .mergeHeadersAndCookies,
            method: .get,
            headers: [
                "User-Agent": "BrowseCraft",
                "Referer": "https://example.test/"
            ],
            cookiePolicy: .browserThenCustom,
            needsWebView: true,
            autoScroll: true
        )
        let httpPageRequest = RequestConfig(
            scope: .page,
            mergePolicy: .mergeHeaders,
            needsWebView: false,
            autoScroll: false
        )
        let readerPageRequest = RequestConfig(
            scope: .reader,
            mergePolicy: .mergeHeadersAndCookies,
            needsWebView: true,
            autoScroll: true
        )
        let rule = SiteRule(
            version: 1,
            sharedRequest: sharedRequest,
            name: "Page Route Source",
            baseUrl: "https://example.test",
            list: ListRule(
                id: "list",
                url: "https://example.test/comics",
                item: ".item",
                title: ".title",
                link: ".title@href",
                type: .comic,
                request: httpPageRequest
            ),
            detail: DetailRule(
                id: "detail",
                title: "h1",
                chapterContainer: "#chapters",
                chapterItem: "a",
                chapterTitle: "this",
                chapterLink: "this@href",
                request: httpPageRequest
            ),
            gallery: GalleryRule(
                id: "reader",
                request: readerPageRequest,
                imageItem: "img.page",
                imageUrl: "this@src"
            )
        )

        return Source(
            id: "page-route-source",
            name: "Page Route Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

private final class RecordingComicRoutePageContentLoader: PageContentLoader {
    struct RecordedRequest {
        let url: URL
        let request: RequestConfig?
    }

    private enum LoaderError: LocalizedError {
        case missingResponse(String)

        var errorDescription: String? {
            switch self {
            case .missingResponse(let url):
                return "Missing response for URL: \(url)"
            }
        }
    }

    private let responses: [String: String]
    private(set) var requests: [RecordedRequest] = []

    init(responses: [String: String]) {
        self.responses = responses
    }

    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        self.requests.append(RecordedRequest(url: url, request: request))
        guard let response: String = self.responses[url.absoluteString] else {
            throw LoaderError.missingResponse(url.absoluteString)
        }
        return response
    }

    func request(for urlString: String) -> RequestConfig? {
        return self.requests.first(where: { request in
            return request.url.absoluteString == urlString
        })?.request
    }
}
