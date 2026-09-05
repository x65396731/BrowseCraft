import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftDomain
import BrowseCraftRuntime

/// Video V2 站内搜索（`BC-SEARCH-007`）：能力由规则声明；URL 模板替换 `{keyword}`；结果按引用的 listRule 解析。
struct VideoSourceRuntimeSearchTests {
    private final class RecordingLoader: PageContentLoader, @unchecked Sendable {
        let html: String
        private(set) var urls: [URL] = []
        private(set) var requests: [RequestConfig?] = []
        init(html: String) { self.html = html }
        func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
            self.urls.append(request.url)
            self.requests.append(request.requestConfig)
            return PageContentResponse(content: self.html, finalURL: request.url)
        }
    }

    private static func rule(searchRules: [VideoSearchRule]?) -> VideoSiteRule {
        return VideoSiteRule(
            version: 2,
            name: "Video V2",
            baseUrl: "https://video.example.invalid/",
            site: SiteConfig(name: "Video V2", domain: "video.example.invalid", baseURL: "https://video.example.invalid/"),
            sharedRequest: RequestConfig(scope: .site, headers: ["X-Site": "site"], needsWebView: false),
            pages: [
                VideoPageRule(
                    id: "latest",
                    title: "Latest",
                    type: .list,
                    url: "/videos/",
                    ruleRefs: VideoRuleRefs(list: "video-list")
                )
            ],
            ruleSets: VideoRuleSets(
                listRules: [
                    VideoListRule(
                        id: "video-list",
                        item: ExtractRule(selector: ".video-card", selectorKind: .css, function: .raw),
                        fields: VideoListFields(
                            title: ExtractRule(selectorKind: .current, function: .text),
                            detailURL: ExtractRule(selectorKind: .current, function: .url, param: "href")
                        )
                    )
                ],
                searchRules: searchRules
            )
        )
    }

    private static func source(rule: VideoSiteRule) -> Source {
        let now: Date = Date(timeIntervalSince1970: 1_000)
        return Source(
            id: "catalog.video.search",
            name: rule.name,
            baseURL: rule.baseUrl,
            type: .html,
            configuration: .video(VideoSourceConfiguration(rule: rule)),
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func context(sourceID: String) -> SourceRuntimeContext {
        return SourceRuntimeContext(
            sourceID: sourceID,
            pageID: nil,
            tabID: nil,
            ruleID: nil,
            requestOverride: nil,
            debugMode: false,
            operation: .search
        )
    }

    @Test func runtimeWithoutSearchRuleDoesNotSupportSearch() throws {
        let rule: VideoSiteRule = Self.rule(searchRules: nil)
        let runtime = VideoSourceRuntime(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            listLoader: VideoSourceListLoader(pageContentLoader: RecordingLoader(html: ""), parser: CoreVideoRuleSourceParser())
        )
        #expect(runtime.capabilities.supportsSearch == false)
        #expect(runtime.capabilities.limitations.contains { $0.capability == .search })
    }

    @Test func searchRendersTheKeywordAndParsesResultsWithTheReferencedListRule() async throws {
        let rule: VideoSiteRule = Self.rule(searchRules: [
            VideoSearchRule(
                id: "search",
                url: "https://video.example.invalid/vodsearch/{keyword}-------------.html",
                keywordEncoding: .percentEncoded,
                listRuleRef: "video-list",
                request: RequestConfig(scope: .rule, headers: ["X-Search": "search"])
            )
        ])
        let loader = RecordingLoader(html: """
        <html><body>
          <a class="video-card" href="/vod/1.html">海贼王</a>
          <a class="video-card" href="/vod/2.html">海贼王 剧场版</a>
        </body></html>
        """)
        let source: Source = Self.source(rule: rule)
        let runtime = VideoSourceRuntime(
            source: source,
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            listLoader: VideoSourceListLoader(pageContentLoader: loader, parser: CoreVideoRuleSourceParser())
        )
        #expect(runtime.capabilities.supportsSearch)

        let output: SourceListOutput = try await runtime.search(
            SourceSearchInput(keyword: "海贼王", page: 1, urlOverride: nil, context: Self.context(sourceID: source.id))
        )

        #expect(loader.urls.map(\.absoluteString) == [
            "https://video.example.invalid/vodsearch/%E6%B5%B7%E8%B4%BC%E7%8E%8B-------------.html"
        ])
        #expect(loader.requests.first??.headers?["X-Site"] == "site")
        #expect(loader.requests.first??.headers?["X-Search"] == "search")
        #expect(output.items.map(\.title) == ["海贼王", "海贼王 剧场版"])
        #expect(output.items.map { $0.detailURL?.absoluteString } == [
            "https://video.example.invalid/vod/1.html",
            "https://video.example.invalid/vod/2.html"
        ])
        #expect(output.pagination == nil)
    }

    @Test func emptyResultPageIsAValidEmptySearchNotAnError() async throws {
        let rule: VideoSiteRule = Self.rule(searchRules: [
            VideoSearchRule(id: "search", url: "https://video.example.invalid/search?wd={keyword}", listRuleRef: "video-list")
        ])
        let source: Source = Self.source(rule: rule)
        let runtime = VideoSourceRuntime(
            source: source,
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            listLoader: VideoSourceListLoader(pageContentLoader: RecordingLoader(html: "<html><body><p>nothing</p></body></html>"), parser: CoreVideoRuleSourceParser())
        )
        let output: SourceListOutput = try await runtime.search(
            SourceSearchInput(keyword: "zzz", page: 1, urlOverride: nil, context: Self.context(sourceID: source.id))
        )
        #expect(output.items.isEmpty)

        await #expect(throws: SourceRuntimeError.self) {
            _ = try await runtime.search(
                SourceSearchInput(keyword: "   ", page: 1, urlOverride: nil, context: Self.context(sourceID: source.id))
            )
        }
    }
}
