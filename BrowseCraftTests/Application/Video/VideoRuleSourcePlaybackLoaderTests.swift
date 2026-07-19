import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

struct VideoRuleSourcePlaybackLoaderTests {
    @Test func directHLSPlaybackUsesFinalPageURLAndStableHandoff() async throws {
        let pageLoader = PlaybackPageContentLoader(
            html: "<html><video><source src=\"/media/master.m3u8\"></video></html>",
            finalURL: try #require(URL(string: "https://video.example.invalid/watch/final?ticket=secret"))
        )
        let rule: VideoSiteRule = Self.playbackRule()
        let output: SourceVideoPlaybackOutput = try await VideoRuleSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: SwiftSoupVideoRuleSourceParser()
        ).execute(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        #expect(output.reference.status == .playable)
        #expect(output.reference.candidateMediaKind == .m3u8)
        #expect(output.reference.candidateMediaURL?.absoluteString == "https://video.example.invalid/media/master.m3u8")
        #expect(output.reference.playbackRequestConfig?.referer?.absoluteString == "https://video.example.invalid/watch/final?ticket=secret")
        #expect(output.reference.playbackRequestConfig?.headers["X-Region"] == "jp")
        #expect(output.reference.playbackRequestConfig?.userAgent == "Fixture/catalog.video.playback")
        #expect(output.reference.episodeKey == "episode-1")
        #expect(output.reference.nextEpisodeURL?.absoluteString == "https://video.example.invalid/watch/2")
        #expect(pageLoader.lastRequest?.headers?["X-Playback"] == "rule")
        #expect(output.diagnostics.requestLogs.first?.url.query == nil)
    }

    @Test func multipleDistinctDirectMediaURLsAreAResponseContractError() async throws {
        let pageLoader = PlaybackPageContentLoader(
            html: """
            <video>
              <source src="/media/one.m3u8">
              <source src="/media/two.m3u8">
            </video>
            """,
            finalURL: try #require(URL(string: "https://video.example.invalid/watch/1"))
        )
        let rule: VideoSiteRule = Self.playbackRule()

        do {
            _ = try await VideoRuleSourcePlaybackLoader(
                pageContentLoader: pageLoader,
                parser: SwiftSoupVideoRuleSourceParser()
            ).execute(
                source: Self.source(rule: rule),
                resolvedRule: try ResolvedVideoSiteRule(validating: rule),
                input: Self.input()
            )
            Issue.record("Expected playback response-contract error.")
        } catch let error as RuleExecutionError {
            guard case .responseContract(.playback, _, let reason) = error else {
                Issue.record("Unexpected playback error: \(error.localizedDescription)")
                return
            }
            #expect(reason.contains("multiple distinct direct media URLs"))
        }
    }

    @Test func emptyMediaExtractionProducesStableFailedReference() async throws {
        let pageLoader = PlaybackPageContentLoader(
            html: "<html><video></video></html>",
            finalURL: try #require(URL(string: "https://video.example.invalid/watch/1"))
        )
        let rule: VideoSiteRule = Self.playbackRule()
        let output: SourceVideoPlaybackOutput = try await VideoRuleSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: SwiftSoupVideoRuleSourceParser()
        ).execute(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        #expect(output.reference.status == .failed(.mediaURLNotFound))
        #expect(output.reference.candidateMediaURL == nil)
        #expect(output.reference.previousEpisodeURL == nil)
        #expect(output.reference.nextEpisodeURL?.absoluteString == "https://video.example.invalid/watch/2")
    }

    @Test func explicitIframeWebUIStrategyProducesPageOnlyReference() async throws {
        let pageLoader = PlaybackPageContentLoader(
            html: #"<iframe src="/embed/player"></iframe>"#,
            finalURL: try #require(URL(string: "https://video.example.invalid/watch/1"))
        )
        var rule: VideoSiteRule = Self.playbackRule()
        rule.ruleSets.playbackRules = [
            VideoPlaybackRule(
                id: "playback",
                iframe: Self.iframeRule(strategy: .webUI)
            )
        ]

        let output: SourceVideoPlaybackOutput = try await VideoRuleSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: SwiftSoupVideoRuleSourceParser()
        ).execute(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        #expect(output.reference.status == .pageOnly)
        #expect(output.reference.candidateMediaKind == .iframePlayer)
        #expect(output.reference.candidateMediaURL?.absoluteString == "https://video.example.invalid/embed/player")
    }

    @Test func iframeResolveStrategyRecursesUntilDirectMediaIsFound() async throws {
        let pageLoader = RoutedPlaybackPageContentLoader(
            responses: [
                "https://video.example.invalid/watch/1": PageContentResponse(
                    content: #"<iframe src="/embed/player"></iframe>"#,
                    finalURL: try #require(URL(string: "https://video.example.invalid/watch/1"))
                ),
                "https://video.example.invalid/embed/player": PageContentResponse(
                    content: #"<video><source src="/media/master.m3u8"></video>"#,
                    finalURL: try #require(URL(string: "https://video.example.invalid/embed/player"))
                )
            ]
        )
        var rule: VideoSiteRule = Self.playbackRule()
        rule.ruleSets.playbackRules?[0].iframe = Self.iframeRule(strategy: .resolve, maxDepth: 2)

        let output: SourceVideoPlaybackOutput = try await VideoRuleSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: SwiftSoupVideoRuleSourceParser()
        ).execute(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        #expect(output.reference.status == .playable)
        #expect(output.reference.candidateMediaURL?.absoluteString == "https://video.example.invalid/media/master.m3u8")
        #expect(pageLoader.requestedURLs.map(\.absoluteString) == [
            "https://video.example.invalid/watch/1",
            "https://video.example.invalid/embed/player"
        ])
    }

    @Test func webUIFallbackMustBeExplicit() async throws {
        let pageLoader = PlaybackPageContentLoader(
            html: "<html><video></video></html>",
            finalURL: try #require(URL(string: "https://video.example.invalid/watch/1"))
        )
        var rule: VideoSiteRule = Self.playbackRule()
        rule.ruleSets.playbackRules?[0].fallback = .webUI

        let output: SourceVideoPlaybackOutput = try await VideoRuleSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: SwiftSoupVideoRuleSourceParser()
        ).execute(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        #expect(output.reference.status == .pageOnly)
        #expect(output.reference.candidateMediaURL?.absoluteString == "https://video.example.invalid/watch/1")
    }

    @Test func mediaCookiePolicyIsPreservedWithoutMaterializingCookieValue() async throws {
        let pageLoader = PlaybackPageContentLoader(
            html: #"<video><source src="/media/master.m3u8"></video>"#,
            finalURL: try #require(URL(string: "https://video.example.invalid/watch/1"))
        )
        var rule: VideoSiteRule = Self.playbackRule()
        rule.ruleSets.playbackRules?[0].mediaRequest?.cookiePolicy = .browser

        let output: SourceVideoPlaybackOutput = try await VideoRuleSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: SwiftSoupVideoRuleSourceParser()
        ).execute(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        #expect(output.reference.playbackRequestConfig?.cookiePolicy == .browser)
        #expect(output.reference.playbackRequestConfig?.headers.keys.contains(where: {
            $0.caseInsensitiveCompare("Cookie") == .orderedSame
        }) == false)
    }
}

private extension VideoRuleSourcePlaybackLoaderTests {
    static func playbackRule() -> VideoSiteRule {
        return VideoSiteRule(
            version: 2,
            name: "Playback V2",
            baseUrl: "https://video.example.invalid/",
            site: SiteConfig(
                name: "Playback V2",
                domain: "video.example.invalid",
                baseURL: "https://video.example.invalid/"
            ),
            context: ["region": SiteRuleContextValue(value: "jp")],
            pages: [
                VideoPageRule(
                    id: "latest",
                    title: "Latest",
                    type: .list,
                    url: "/videos/",
                    ruleRefs: VideoRuleRefs(
                        list: "list",
                        detail: "detail",
                        episode: "episodes",
                        playback: "playback"
                    )
                )
            ],
            ruleSets: VideoRuleSets(
                listRules: [VideoListRule(id: "list")],
                detailRules: [VideoDetailRule(id: "detail")],
                episodeRules: [VideoEpisodeRule(id: "episodes")],
                playbackRules: [
                    VideoPlaybackRule(
                        id: "playback",
                        media: VideoDirectMediaRule(
                            url: ExtractRule(
                                selector: "video source[src]",
                                selectorKind: .css,
                                function: .attr,
                                param: "src"
                            ),
                            kind: .hls
                        ),
                        request: RequestConfig(
                            scope: .rule,
                            headers: ["X-Playback": "rule"]
                        ),
                        mediaRequest: VideoMediaRequestRule(
                            headers: ["X-Region": "{context.region}"],
                            referer: "{playback.finalURL.absoluteString}",
                            userAgent: "Fixture/{source.id}"
                        )
                    )
                ]
            )
        )
    }

    static func source(rule: VideoSiteRule) -> Source {
        let now = Date(timeIntervalSince1970: 1_000)
        return Source(
            id: "catalog.video.playback",
            name: rule.name,
            baseURL: rule.baseUrl,
            type: .html,
            configuration: .video(VideoSourceConfiguration(rule: rule)),
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }

    static func iframeRule(
        strategy: VideoIframePlaybackStrategy,
        maxDepth: Int? = nil
    ) -> VideoIframePlaybackRule {
        return VideoIframePlaybackRule(
            url: ExtractRule(
                selector: "iframe[src]",
                selectorKind: .css,
                function: .attr,
                param: "src"
            ),
            strategy: strategy,
            maxDepth: maxDepth
        )
    }

    static func input() throws -> SourceVideoPlaybackInput {
        let firstURL: URL = try #require(URL(string: "https://video.example.invalid/watch/1"))
        let secondURL: URL = try #require(URL(string: "https://video.example.invalid/watch/2"))
        return SourceVideoPlaybackInput(
            playPageURL: firstURL,
            context: SourceRuntimeContext(
                sourceID: "catalog.video.playback",
                pageID: "latest",
                tabID: "latest",
                ruleID: "list",
                requestOverride: nil,
                debugMode: false
            ),
            handoff: SourceVideoPlaybackHandoff(
                vodID: "movie-1",
                sourceIndex: 1,
                episodeIndex: 1,
                episodeKey: "episode-1",
                episodeTitle: "Episode 1",
                episodeURLs: [firstURL, secondURL],
                episodeKeys: ["episode-1", "episode-2"],
                episodeTitles: ["Episode 1", "Episode 2"],
                sourceName: "Route A",
                pageID: "latest",
                listRuleID: "list"
            )
        )
    }
}

private final class PlaybackPageContentLoader: ContextualPageContentResponseLoader {
    let html: String
    let finalURL: URL
    private(set) var lastRequest: RequestConfig?

    init(html: String, finalURL: URL) {
        self.html = html
        self.finalURL = finalURL
    }

    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        self.lastRequest = request
        return self.html
    }

    func getString(
        from url: URL,
        request: RequestConfig?,
        context: SourceRequestContext?
    ) async throws -> String {
        self.lastRequest = request
        return self.html
    }

    func getStringResponse(
        from url: URL,
        request: RequestConfig?,
        context: SourceRequestContext?
    ) async throws -> PageContentResponse {
        self.lastRequest = request
        return PageContentResponse(content: self.html, finalURL: self.finalURL)
    }
}

private final class RoutedPlaybackPageContentLoader: ContextualPageContentResponseLoader {
    let responses: [String: PageContentResponse]
    private(set) var requestedURLs: [URL] = []

    init(responses: [String: PageContentResponse]) {
        self.responses = responses
    }

    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        return try await self.getStringResponse(from: url, request: request, context: nil).content
    }

    func getString(
        from url: URL,
        request: RequestConfig?,
        context: SourceRequestContext?
    ) async throws -> String {
        return try await self.getStringResponse(from: url, request: request, context: context).content
    }

    func getStringResponse(
        from url: URL,
        request: RequestConfig?,
        context: SourceRequestContext?
    ) async throws -> PageContentResponse {
        self.requestedURLs.append(url)
        guard let response: PageContentResponse = self.responses[url.absoluteString] else {
            throw SourceRuntimeError.invalidInput("Missing routed playback response.")
        }
        return response
    }
}
