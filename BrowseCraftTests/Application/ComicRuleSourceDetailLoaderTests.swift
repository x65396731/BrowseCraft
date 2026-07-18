import Foundation
import Testing
@testable import BrowseCraft

struct ComicRuleSourceDetailLoaderTests {
    @Test func preferredChapterAPILoadsBeforeDetailHTML() async throws {
        let pageContentLoader: RecordingChapterPageContentLoader = RecordingChapterPageContentLoader(
            responses: [
                "https://example.test/api/comic/5571": """
                {
                  "chapters": [
                    { "title": "第01话", "url": "/comic/5571/chapter/1" },
                    { "title": "第02话", "url": "/comic/5571/chapter/2" }
                  ]
                }
                """
            ],
            disallowedURLs: ["https://example.test/comic/5571"]
        )
        let loader: ComicRuleSourceDetailLoader = ComicRuleSourceDetailLoader(
            pageContentLoader: pageContentLoader,
            comicRuleParser: SwiftSoupComicRuleSourceParser(urlResolver: URLResolvingService())
        )

        let content: ChapterDetailContent = try await loader.execute(
            source: Self.sourceWithPreferredChapterAPI(),
            item: ContentItem(
                id: "comic-5571",
                sourceId: "preferred-api-source",
                title: "小栗子到我家",
                detailURL: "https://example.test/comic/5571",
                coverURL: nil,
                type: .comic,
                latestText: "连载19话"
            )
        )

        #expect(content.chapters.map(\.title) == ["第01话", "第02话"])
        #expect(content.chapters.map(\.url) == [
            "https://example.test/comic/5571/chapter/1",
            "https://example.test/comic/5571/chapter/2"
        ])
        #expect(pageContentLoader.requestedURLs == ["https://example.test/api/comic/5571"])
        #expect(pageContentLoader.requestBodies == [
            """
            {"query":"query chaptersByComicId($comicId: ID!) { chaptersByComicId(comicId: $comicId) { id title url } }","variables":{"comicId":"5571"}}
            """
        ])
    }

    @Test func preferredChapterAPIStillLoadsConfiguredDetailMetadata() async throws {
        let pageContentLoader: RecordingChapterPageContentLoader = RecordingChapterPageContentLoader(
            responses: [
                "https://example.test/comic/5571": """
                <main>
                  <h1>小栗子到我家</h1>
                  <img class="cover" src="/covers/5571.jpg">
                  <p class="author">作者甲</p>
                </main>
                """,
                "https://example.test/api/comic/5571": """
                {
                  "chapters": [
                    { "title": "第01话", "url": "/comic/5571/chapter/1" }
                  ]
                }
                """
            ],
            disallowedURLs: []
        )
        let loader: ComicRuleSourceDetailLoader = ComicRuleSourceDetailLoader(
            pageContentLoader: pageContentLoader,
            comicRuleParser: SwiftSoupComicRuleSourceParser(urlResolver: URLResolvingService())
        )
        var source: Source = Self.sourceWithPreferredChapterAPI()
        source.rule.detail?.fields = DetailFields(
            title: ExtractRule(selector: "h1", function: .text),
            cover: ExtractRule(selector: "img.cover", function: .attr, param: "src"),
            author: ExtractRule(selector: ".author", function: .text)
        )

        let content: ComicRuleParsedDetail = try await loader.execute(
            source: source,
            item: ContentItem(
                id: "comic-5571",
                sourceId: "preferred-api-source",
                title: "列表标题",
                detailURL: "https://example.test/comic/5571",
                coverURL: nil,
                type: .comic,
                latestText: "连载19话"
            )
        )

        #expect(content.metadata.title == "小栗子到我家")
        #expect(content.metadata.coverURL == "https://example.test/covers/5571.jpg")
        #expect(content.metadata.author == "作者甲")
        #expect(content.chapters.map(\.title) == ["第01话"])
        #expect(pageContentLoader.requestedURLs == [
            "https://example.test/comic/5571",
            "https://example.test/api/comic/5571"
        ])
    }

    private static func sourceWithPreferredChapterAPI() -> Source {
        let rule: SiteRule = SiteRule(
            version: 1,
            site: nil,
            urlPatterns: nil,
            pages: nil,
            ruleSets: nil,
            sharedRequest: nil,
            flags: nil,
            name: "Preferred API Source",
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
                chapterAPI: DetailChapterAPIRule(
                    url: "https://example.test/api/comic/{detailSlug}",
                    request: RequestConfig(
                        method: .post,
                        headers: [
                            "Accept": "application/json",
                            "Content-Type": "application/json"
                        ],
                        body: RequestBody(
                            contentType: "application/json",
                            value: """
                            {"query":"query chaptersByComicId($comicId: ID!) { chaptersByComicId(comicId: $comicId) { id title url } }","variables":{"comicId":"{detailSlug}"}}
                            """
                        )
                    ),
                    itemPath: "chapters[]",
                    titlePath: "title",
                    urlPath: "url",
                    preferAPI: true
                ),
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
            id: "preferred-api-source",
            name: "Preferred API Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

private final class RecordingChapterPageContentLoader: PageContentLoader {
    private enum LoaderError: LocalizedError {
        case disallowedURL(String)
        case missingResponse(String)

        var errorDescription: String? {
            switch self {
            case .disallowedURL(let url):
                return "Unexpected request to disallowed URL: \(url)"
            case .missingResponse(let url):
                return "Missing response for URL: \(url)"
            }
        }
    }

    private let responses: [String: String]
    private let disallowedURLs: Set<String>
    private(set) var requestedURLs: [String] = []
    private(set) var requestBodies: [String] = []

    init(responses: [String: String], disallowedURLs: Set<String>) {
        self.responses = responses
        self.disallowedURLs = disallowedURLs
    }

    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        let urlString: String = url.absoluteString
        self.requestedURLs.append(urlString)
        if let body: RequestBody = request?.body {
            self.requestBodies.append(body.value)
        }

        if self.disallowedURLs.contains(urlString) {
            throw LoaderError.disallowedURL(urlString)
        }

        guard let response: String = self.responses[urlString] else {
            throw LoaderError.missingResponse(urlString)
        }

        return response
    }
}
