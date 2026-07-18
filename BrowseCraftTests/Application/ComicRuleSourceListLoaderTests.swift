import Foundation
import Testing
@testable import BrowseCraft

struct ComicRuleSourceListLoaderTests {
    @Test func preferredListAPILoadsItemsBeforeListHTML() async throws {
        let pageContentLoader: RecordingListPageContentLoader = RecordingListPageContentLoader(
            responses: [
                "https://example.test/api/comics?page=1": """
                {
                  "data": {
                    "comics": [
                      { "id": "5571", "title": "小栗子到我家", "imageToken": "cover-5571", "latest": "连载19话", "sort": 2 },
                      { "id": "8601", "title": "必杀千金丽泽", "imageToken": "cover-8601", "latest": "连载02话", "sort": 1 }
                    ]
                  }
                }
                """
            ],
            disallowedURLs: ["https://example.test/updates"]
        )
        let loader: ComicRuleSourceListLoader = Self.loader(pageContentLoader: pageContentLoader)

        let items: [ContentItem] = try await loader.execute(source: Self.sourceWithPreferredListAPI())

        #expect(items.map(\.title) == ["必杀千金丽泽", "小栗子到我家"])
        #expect(items.map(\.detailURL) == [
            "https://example.test/comic/8601",
            "https://example.test/comic/5571"
        ])
        #expect(items.map(\.coverURL) == [
            "https://example.test/api/image/cover-8601",
            "https://example.test/api/image/cover-5571"
        ])
        #expect(items.map(\.latestText) == ["连载02话", "连载19话"])
        #expect(items.map(\.listOrder) == [0, 1])
        #expect(pageContentLoader.requestedURLs == ["https://example.test/api/comics?page=1"])
    }

    @Test func emptyPreferredListAPIFallsBackToDOMList() async throws {
        let pageContentLoader: RecordingListPageContentLoader = RecordingListPageContentLoader(
            responses: [
                "https://example.test/api/comics?page=1": """
                { "data": { "comics": [] } }
                """,
                "https://example.test/updates": """
                <main>
                  <article class="item">
                    <a href="/comic/dom">DOM 漫画</a>
                    <img src="/covers/dom.jpg">
                    <span class="latest">连载01话</span>
                  </article>
                </main>
                """
            ],
            disallowedURLs: []
        )
        let loader: ComicRuleSourceListLoader = Self.loader(pageContentLoader: pageContentLoader)

        let items: [ContentItem] = try await loader.execute(source: Self.sourceWithPreferredListAPI())

        #expect(pageContentLoader.requestedURLs == [
            "https://example.test/api/comics?page=1",
            "https://example.test/updates"
        ])
        #expect(items.count == 1)
        #expect(items[0].title == "DOM 漫画")
        #expect(items[0].detailURL == "https://example.test/comic/dom")
        #expect(items[0].coverURL == "https://example.test/covers/dom.jpg")
    }

    @Test func listAPIRequestInheritsSharedHeadersAndAppliesAPIOverrides() async throws {
        let pageContentLoader: RecordingListPageContentLoader = RecordingListPageContentLoader(
            responses: [
                "https://example.test/api/comics?page=1": """
                {
                  "data": {
                    "comics": [
                      { "id": "5571", "title": "小栗子到我家" }
                    ]
                  }
                }
                """
            ],
            disallowedURLs: ["https://example.test/updates"]
        )
        let loader: ComicRuleSourceListLoader = Self.loader(pageContentLoader: pageContentLoader)

        _ = try await loader.execute(source: Self.sourceWithMergedListAPIRequest())

        let request: RequestConfig = try #require(pageContentLoader.requests.first)
        #expect(request.headers?["device"] == "server")
        #expect(request.headers?["uuid"] == "rule-uuid")
        #expect(request.headers?["Accept-Language"] == "zh")
        #expect(request.headers?["Accept"] == "application/json")
        #expect(request.scope == .rule)
        #expect(request.needsWebView == false)
    }

    @Test func listAPIErrorCodeThrowsSourceAPIInsteadOfFallingBackToDOM() async throws {
        let pageContentLoader: RecordingListPageContentLoader = RecordingListPageContentLoader(
            responses: [
                "https://example.test/api/comics?page=1": """
                { "code": 403, "message": "uuid錯誤" }
                """
            ],
            disallowedURLs: ["https://example.test/updates"]
        )
        let loader: ComicRuleSourceListLoader = Self.loader(pageContentLoader: pageContentLoader)

        do {
            _ = try await loader.execute(source: Self.sourceWithPreferredListAPI())
            Issue.record("Expected sourceAPI error")
        } catch let error as RuleExecutionError {
            guard case .sourceAPI(let stage, let sourceID, let reason) = error else {
                Issue.record("Expected sourceAPI error, got \(error)")
                return
            }
            #expect(stage == .list)
            #expect(sourceID == "preferred-list-api-source")
            #expect(reason.contains("uuid錯誤"))
            #expect(reason.contains("code=403"))
            #expect(pageContentLoader.requestedURLs == ["https://example.test/api/comics?page=1"])
        }
    }

    @Test func explicitResponsePolicyAcceptsNumericBusinessStatus200() async throws {
        let pageContentLoader = RecordingListPageContentLoader(
            responses: [
                "https://example.test/api/comics?page=1": """
                {
                  "code": 200,
                  "message": "OK",
                  "data": {
                    "comics": [
                      { "id": "5571", "title": "小栗子到我家" }
                    ]
                  }
                }
                """
            ],
            disallowedURLs: ["https://example.test/updates"]
        )
        let responsePolicy = APIResponsePolicy(
            mode: .envelope,
            businessStatusPath: "code",
            successValues: [.number(200)],
            failurePaths: ["errors[]", "error"],
            messagePaths: ["message"]
        )
        let loader = Self.loader(pageContentLoader: pageContentLoader)

        let items = try await loader.execute(
            source: Self.sourceWithPreferredListAPI(responsePolicy: responsePolicy)
        )

        #expect(items.map(\.title) == ["小栗子到我家"])
        #expect(pageContentLoader.requestedURLs == ["https://example.test/api/comics?page=1"])
    }

    @Test func explicitResponsePolicyRejectsUnlistedBusinessStatus() async throws {
        let pageContentLoader = RecordingListPageContentLoader(
            responses: [
                "https://example.test/api/comics?page=1": """
                { "code": 403, "message": "uuid錯誤" }
                """
            ],
            disallowedURLs: ["https://example.test/updates"]
        )
        let responsePolicy = APIResponsePolicy(
            mode: .envelope,
            businessStatusPath: "code",
            successValues: [.number(200)],
            messagePaths: ["message"]
        )
        let loader = Self.loader(pageContentLoader: pageContentLoader)

        do {
            _ = try await loader.execute(
                source: Self.sourceWithPreferredListAPI(responsePolicy: responsePolicy)
            )
            Issue.record("Expected explicit response policy failure")
        } catch let error as RuleExecutionError {
            guard case .sourceAPI(_, _, let reason) = error else {
                Issue.record("Expected sourceAPI error, got \(error)")
                return
            }
            #expect(reason.contains("uuid錯誤"))
            #expect(reason.contains("code=403"))
        }
    }

    @Test func explicitResponsePolicyKeepsNumericAndStringStatusDistinct() async throws {
        let pageContentLoader = RecordingListPageContentLoader(
            responses: [
                "https://example.test/api/comics?page=1": """
                { "code": "200", "message": "string status is not numeric" }
                """
            ],
            disallowedURLs: ["https://example.test/updates"]
        )
        let responsePolicy = APIResponsePolicy(
            mode: .envelope,
            businessStatusPath: "code",
            successValues: [.number(200)],
            messagePaths: ["message"]
        )
        let loader = Self.loader(pageContentLoader: pageContentLoader)

        do {
            _ = try await loader.execute(
                source: Self.sourceWithPreferredListAPI(responsePolicy: responsePolicy)
            )
            Issue.record("Expected string business status to differ from numeric status")
        } catch let error as RuleExecutionError {
            guard case .sourceAPI(_, _, let reason) = error else {
                Issue.record("Expected sourceAPI error, got \(error)")
                return
            }
            #expect(reason.contains("string status is not numeric"))
            #expect(reason.contains("code=200"))
        }
    }

    @Test func transportOnlyResponsePolicyDoesNotStackLegacyCodeCheck() async throws {
        let pageContentLoader = RecordingListPageContentLoader(
            responses: [
                "https://example.test/api/comics?page=1": """
                {
                  "code": 403,
                  "data": {
                    "comics": [
                      { "id": "5571", "title": "传输层规则" }
                    ]
                  }
                }
                """
            ],
            disallowedURLs: ["https://example.test/updates"]
        )
        let loader = Self.loader(pageContentLoader: pageContentLoader)

        let items = try await loader.execute(
            source: Self.sourceWithPreferredListAPI(
                responsePolicy: APIResponsePolicy(mode: .transportOnly)
            )
        )

        #expect(items.map(\.title) == ["传输层规则"])
    }

    @Test func nonemptyAPIItemsThatAllFailMappingRemainContractErrors() async throws {
        let pageContentLoader = RecordingListPageContentLoader(
            responses: [
                "https://example.test/api/comics?page=1": """
                { "data": { "comics": [{ "id": "missing-title" }] } }
                """
            ],
            disallowedURLs: ["https://example.test/updates"]
        )
        let loader = Self.loader(pageContentLoader: pageContentLoader)

        do {
            _ = try await loader.execute(source: Self.sourceWithPreferredListAPI())
            Issue.record("Expected API mapping contract failure")
        } catch let error as RuleExecutionError {
            guard case .apiResponseContract(_, _, let reason) = error else {
                Issue.record("Expected apiResponseContract, got \(error)")
                return
            }
            #expect(reason.contains("all item mappings failed"))
            #expect(pageContentLoader.requestedURLs == ["https://example.test/api/comics?page=1"])
        }
    }

    private static func loader(pageContentLoader: PageContentLoader) -> ComicRuleSourceListLoader {
        return ComicRuleSourceListLoader(
            pageContentLoader: pageContentLoader,
            comicRuleParser: SwiftSoupComicRuleSourceParser(urlResolver: URLResolvingService()),
            urlResolver: URLResolvingService()
        )
    }

    private static func sourceWithPreferredListAPI(
        responsePolicy: APIResponsePolicy? = nil
    ) -> Source {
        let rule: SiteRule = SiteRule(
            version: 1,
            site: nil,
            urlPatterns: nil,
            pages: nil,
            ruleSets: nil,
            sharedRequest: nil,
            flags: nil,
            name: "Preferred List API Source",
            baseUrl: "https://example.test",
            list: ListRule(
                id: "updates",
                url: "https://example.test/updates",
                item: ".item",
                title: "a",
                link: "a@href",
                cover: "img@src",
                type: .comic,
                latestText: ".latest",
                listAPI: ListAPIRule(
                    url: "https://example.test/api/comics?page={page}",
                    itemPath: "data.comics[]",
                    titlePath: "title",
                    urlTemplate: "https://example.test/comic/{id}",
                    coverTemplate: "https://example.test/api/image/{imageToken}",
                    latestTextPath: "latest",
                    orderPath: "sort",
                    sort: .ascending,
                    preferAPI: true,
                    responsePolicy: responsePolicy
                )
            ),
            listTabs: nil,
            detail: DetailRule(
                id: "detail",
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
            id: "preferred-list-api-source",
            name: "Preferred List API Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func sourceWithMergedListAPIRequest() -> Source {
        let rule: SiteRule = SiteRule(
            version: 1,
            site: nil,
            urlPatterns: nil,
            pages: nil,
            ruleSets: nil,
            sharedRequest: RequestConfig(
                scope: .site,
                headers: [
                    "device": "server",
                    "uuid": "rule-uuid",
                    "Accept-Language": "zh",
                    "Accept": "text/html"
                ],
                needsWebView: false
            ),
            flags: nil,
            name: "Merged List API Request Source",
            baseUrl: "https://example.test",
            list: ListRule(
                id: "updates",
                url: "https://example.test/updates",
                item: ".item",
                title: "a",
                link: "a@href",
                cover: nil,
                type: .comic,
                latestText: nil,
                listAPI: ListAPIRule(
                    url: "https://example.test/api/comics?page={page}",
                    request: RequestConfig(
                        scope: .rule,
                        mergePolicy: .mergeHeaders,
                        headers: ["Accept": "application/json"]
                    ),
                    itemPath: "data.comics[]",
                    titlePath: "title",
                    urlTemplate: "https://example.test/comic/{id}",
                    preferAPI: true
                )
            ),
            listTabs: nil,
            detail: DetailRule(
                id: "detail",
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
            id: "merged-list-api-request-source",
            name: "Merged List API Request Source",
            baseURL: "https://example.test",
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

struct ComicRuleAPIResponseEvaluatorTests {
    @Test func missingPolicyPreservesLegacyCodeZeroSuccess() {
        let json: [String: Any] = ["code": 0, "data": ["items": [Any]()]]
        let result = ComicRuleAPIResponseEvaluator.evaluate(
            json: json,
            responsePolicy: nil
        )

        #expect(result == .allowParsing)
    }

    @Test func missingPolicyPreservesLegacyNonzeroCodeFailure() {
        let json: [String: Any] = ["code": 200, "message": "legacy response"]
        let result = ComicRuleAPIResponseEvaluator.evaluate(
            json: json,
            responsePolicy: nil
        )

        #expect(result == .businessFailure(message: "legacy response code=200"))
    }

    @Test func missingPolicyPreservesLegacyErrorsDetails() {
        let extensions: [String: Any] = ["code": "LIMIT", "current": 3]
        let legacyError: [String: Any] = [
            "message": "rate limited",
            "extensions": extensions
        ]
        let json: [String: Any] = ["errors": [legacyError]]
        let result = ComicRuleAPIResponseEvaluator.evaluate(
            json: json,
            responsePolicy: nil
        )

        #expect(result == .businessFailure(message: "rate limited code=LIMIT current=3"))
    }

    @Test func explicitEnvelopeNeverRunsLegacyErrorInference() {
        let json: [String: Any] = ["code": 200, "error": "legacy-only field"]
        let result = ComicRuleAPIResponseEvaluator.evaluate(
            json: json,
            responsePolicy: APIResponsePolicy(
                mode: .envelope,
                businessStatusPath: "code",
                successValues: [.number(200)]
            )
        )

        #expect(result == .allowParsing)
    }
}

struct ComicRuleAPIJSONArrayResolutionTests {
    @Test func distinguishesMissingNullTypeMismatchEmptyAndValues() {
        let root: [String: Any] = [
            "nullItems": NSNull(),
            "wrongItems": "not-an-array",
            "emptyItems": [Any](),
            "items": [["id": 1], ["id": 2]]
        ]

        #expect(ComicRuleAPIResolver.jsonArrayResolution(at: "missingItems[]", in: root).state == .missing)
        #expect(ComicRuleAPIResolver.jsonArrayResolution(at: "nullItems[]", in: root).state == .null)
        #expect(ComicRuleAPIResolver.jsonArrayResolution(at: "wrongItems[]", in: root).state == .typeMismatch)
        #expect(ComicRuleAPIResolver.jsonArrayResolution(at: "emptyItems[]", in: root).state == .empty)

        let values = ComicRuleAPIResolver.jsonArrayResolution(at: "items[]", in: root)
        #expect(values.state == .nonEmpty)
        #expect(values.values.count == 2)
    }
}

private final class RecordingListPageContentLoader: PageContentLoader {
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
    private(set) var requests: [RequestConfig] = []

    init(responses: [String: String], disallowedURLs: Set<String>) {
        self.responses = responses
        self.disallowedURLs = disallowedURLs
    }

    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        let urlString: String = url.absoluteString
        self.requestedURLs.append(urlString)
        if let request: RequestConfig {
            self.requests.append(request)
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
