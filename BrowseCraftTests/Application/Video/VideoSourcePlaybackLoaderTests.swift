import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

struct VideoSourcePlaybackLoaderTests {
    @Test func legacySingleMediaHLSPlaybackUsesFinalPageURLAndStableHandoff() async throws {
        let pageLoader = PlaybackPageContentLoader(
            html: "<html><video><source src=\"/media/master.m3u8\"></video></html>",
            finalURL: try #require(URL(string: "https://video.example.invalid/watch/final?ticket=secret"))
        )
        let rule: VideoSiteRule = Self.playbackRule()
        let output: SourceVideoPlaybackOutput = try await VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
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
        #expect(pageLoader.lastRequest?.headers?["X-Region"] == "jp")
        #expect(pageLoader.lastRequest?.headers?["Referer"] == "https://video.example.invalid/watch/final?ticket=secret")
        #expect(pageLoader.lastRequest?.headers?["Origin"] == "https://video.example.invalid")
        #expect(pageLoader.lastRequest?.headers?["User-Agent"] == "Fixture/catalog.video.playback")
        #expect(pageLoader.lastRequest?.headers?["X-Playback"] == nil)
        #expect(pageLoader.lastRequest?.needsWebView == false)
        #expect(pageLoader.lastRequest?.autoScroll == false)
        #expect(output.diagnostics.requestLogs.first?.url.query == nil)
    }

    @Test func detailOwnedPlaybackUsesTheSameLoaderWithoutEpisodeRule() async throws {
        let pageLoader = PlaybackPageContentLoader(
            html: "<html><video><source src=\"/media/detail.mp4\"></video></html>",
            finalURL: try #require(URL(string: "https://video.example.invalid/detail/movie-1"))
        )
        var rule: VideoSiteRule = Self.playbackRule()
        rule.pages[0].ruleRefs.episode = nil
        rule.ruleSets.episodeRules = nil
        var playbackRules: [VideoPlaybackRule] = rule.ruleSets.playbackRules ?? []
        playbackRules[0].media = VideoDirectMediaRule(
            url: ExtractRule(
                selector: "video source[src]",
                selectorKind: .css,
                function: .attr,
                param: "src"
            ),
            kind: .mp4
        )
        rule.ruleSets.playbackRules = playbackRules
        let resolvedRule = try ResolvedVideoSiteRule(validating: rule)

        let output: SourceVideoPlaybackOutput = try await VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
        ).execute(
            source: Self.source(rule: rule),
            resolvedRule: resolvedRule,
            input: Self.input()
        )

        #expect(resolvedRule.playbackEntries.first?.owner == .detail)
        #expect(output.reference.status == .playable)
        #expect(output.reference.candidateMediaKind == .mp4)
        #expect(output.reference.candidateMediaURL?.absoluteString == "https://video.example.invalid/media/detail.mp4")
    }

    @Test func multipleDistinctLegacyDirectMediaURLsChooseFirstInDocumentOrder() async throws {
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

        let output: SourceVideoPlaybackOutput = try await VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
        ).execute(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        #expect(output.reference.status == .playable)
        #expect(output.reference.candidateMediaKind == .m3u8)
        #expect(output.reference.candidateMediaURL?.absoluteString == "https://video.example.invalid/media/one.m3u8")
    }

    @Test func coreAdapterPreservesOrderedHLSAndMP4Candidates() throws {
        let playbackRule = VideoPlaybackRule(
            id: "playback",
            mediaCandidates: [
                Self.directMediaRule(
                    id: "preferred-hls",
                    title: "Adaptive",
                    selector: "source.hls[src]",
                    kind: .hls
                ),
                Self.directMediaRule(
                    id: "fallback-mp4",
                    title: "MP4",
                    selector: "source.mp4[src]",
                    kind: .mp4
                )
            ]
        )

        let parsed: VideoRuleParsedPlayback = try CoreVideoRuleSourceParser().parsePlayback(
            html: """
            <video>
              <source class="mp4" src="/media/movie.mp4">
              <source class="hls" src="/media/master.m3u8">
            </video>
            """,
            pageURL: try #require(URL(string: "https://video.example.invalid/watch/1")),
            rule: playbackRule
        )

        #expect(parsed.mediaCandidates.map(\.ruleID) == ["preferred-hls", "fallback-mp4"])
        #expect(parsed.mediaCandidates.map(\.title) == ["Adaptive", "MP4"])
        #expect(parsed.mediaCandidates.map(\.kind) == [.hls, .mp4])
        #expect(parsed.mediaURLs == parsed.mediaCandidates.map(\.url))
    }

    @Test func preferredTypedCandidateUsesItsOwnExplicitKind() async throws {
        let pageLoader = PlaybackPageContentLoader(
            html: """
            <video>
              <source class="hls" src="/media/master.m3u8">
              <source class="mp4" src="/media/movie.mp4">
            </video>
            """,
            finalURL: try #require(URL(string: "https://video.example.invalid/watch/1"))
        )
        var rule: VideoSiteRule = Self.playbackRule()
        rule.ruleSets.playbackRules = [
            VideoPlaybackRule(
                id: "playback",
                mediaCandidates: [
                    Self.directMediaRule(
                        id: "preferred-mp4",
                        title: "MP4",
                        selector: "source.mp4[src]",
                        kind: .mp4
                    ),
                    Self.directMediaRule(
                        id: "fallback-hls",
                        title: "Adaptive",
                        selector: "source.hls[src]",
                        kind: .hls
                    )
                ]
            )
        ]

        let output: SourceVideoPlaybackOutput = try await VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
        ).execute(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        #expect(output.reference.status == .playable)
        #expect(output.reference.candidateMediaKind == .mp4)
        #expect(output.reference.candidateMediaURL?.absoluteString == "https://video.example.invalid/media/movie.mp4")
        #expect(output.diagnostics.extractionLogs.first?.selector == "source.mp4[src] | source.hls[src]")
    }

    @Test func emptyMediaExtractionProducesStableFailedReference() async throws {
        let pageLoader = PlaybackPageContentLoader(
            html: "<html><video></video></html>",
            finalURL: try #require(URL(string: "https://video.example.invalid/watch/1"))
        )
        let rule: VideoSiteRule = Self.playbackRule()
        let output: SourceVideoPlaybackOutput = try await VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
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

        let output: SourceVideoPlaybackOutput = try await VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
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

        let output: SourceVideoPlaybackOutput = try await VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
        ).execute(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        #expect(output.reference.status == .playable)
        #expect(output.reference.candidateMediaURL?.absoluteString == "https://video.example.invalid/media/master.m3u8")
        #expect(pageLoader.requestedURLs.map(\.absoluteString) == [
            "https://video.example.invalid/watch/1",
            "https://video.example.invalid/embed/player",
            "https://video.example.invalid/media/master.m3u8"
        ])
    }

    @Test func webUIFallbackMustBeExplicit() async throws {
        let pageLoader = PlaybackPageContentLoader(
            html: "<html><video></video></html>",
            finalURL: try #require(URL(string: "https://video.example.invalid/watch/1"))
        )
        var rule: VideoSiteRule = Self.playbackRule()
        rule.ruleSets.playbackRules?[0].fallback = .webUI

        let output: SourceVideoPlaybackOutput = try await VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
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

        let output: SourceVideoPlaybackOutput = try await VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
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

    @Test func hlsManifestClassifierRejectsExplicitEncryptionTags() {
        #expect(
            VideoHLSManifestEncryptionClassifier.classify(
                "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"https://keys.example.invalid/a\""
            ) == .encrypted
        )
        #expect(
            VideoHLSManifestEncryptionClassifier.classify(
                "#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"skd://asset\""
            ) == .encrypted
        )
        #expect(
            VideoHLSManifestEncryptionClassifier.classify(
                "#EXTM3U\n#EXT-X-SESSION-KEY:METHOD=AES-128,URI=\"https://keys.example.invalid/session\""
            ) == .encrypted
        )
    }

    @Test func hlsManifestClassifierKeepsUnprovenInputsUnknown() {
        let truncatedBeforeEncryptionTag: String = "#EXTM3U\n"
            + String(repeating: "# bounded-padding\n", count: 20_000)
            + "#EXT-X-KEY:METHOD=AES-128,URI=\"https://keys.example.invalid/late\""

        #expect(
            VideoHLSManifestEncryptionClassifier.classify(
                "#EXTM3U\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:10,\nsegment.ts"
            ) == .unknown
        )
        #expect(
            VideoHLSManifestEncryptionClassifier.classify(
                "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nsegment.ts"
            ) == .unknown
        )
        #expect(VideoHLSManifestEncryptionClassifier.classify("<html>not hls</html>") == .unknown)
        #expect(VideoHLSManifestEncryptionClassifier.classify(truncatedBeforeEncryptionTag) == .unknown)
    }

    @Test func unknownHLSUsesResolvedRequestAndSkipsDeclaredFallback() async throws {
        let pageURL: URL = try #require(URL(string: "https://video.example.invalid/watch/1"))
        let mediaURL: URL = try #require(URL(string: "https://video.example.invalid/media/master.m3u8"))
        let pageLoader = RoutedPlaybackPageContentLoader(
            responses: [
                pageURL.absoluteString: PageContentResponse(
                    content: #"<video><source src="/media/master.m3u8"></video>"#,
                    finalURL: pageURL
                ),
                mediaURL.absoluteString: PageContentResponse(
                    content: "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nsegment.ts",
                    finalURL: mediaURL
                )
            ]
        )
        var rule: VideoSiteRule = Self.playbackRule()
        rule.ruleSets.playbackRules?[0].fallback = .webUI
        rule.ruleSets.playbackRules?[0].mediaRequest?.cookiePolicy = .browser
        let loader = VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
        )
        let session: VideoPreparedPlaybackExecutionSession = try loader.prepare(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        let result: VideoPreparedPlaybackExecutionResult = try await loader.executeWithRouteFacts(session)

        #expect(result.output.reference.status == .playable)
        #expect(result.output.reference.candidateMediaURL == mediaURL)
        #expect(result.routeFacts.map(\.routeSlot) == [.media, .fallback])
        #expect(result.routeFacts[0].disposition == .selectedForPlayer)
        #expect(result.routeFacts[0].reason == nil)
        #expect(result.routeFacts[1].disposition == .skipped)
        #expect(result.routeFacts[1].reason == .priorRouteSelected)
        let manifestRequest: RequestConfig? = pageLoader.requests.last?.requestConfig
        #expect(manifestRequest?.headers?["X-Region"] == "jp")
        #expect(manifestRequest?.headers?["Referer"] == pageURL.absoluteString)
        #expect(manifestRequest?.headers?["Origin"] == "https://video.example.invalid")
        #expect(manifestRequest?.headers?["User-Agent"] == "Fixture/catalog.video.playback")
        #expect(manifestRequest?.cookiePolicy == .browser)
        #expect(manifestRequest?.headers?.keys.contains(where: {
            $0.caseInsensitiveCompare("Cookie") == .orderedSame
        }) == false)
        #expect(manifestRequest?.needsWebView == false)
        #expect(manifestRequest?.autoScroll == false)
    }

    @Test func failedManifestInspectionKeepsHLSPlayable() async throws {
        let pageURL: URL = try #require(URL(string: "https://video.example.invalid/watch/1"))
        let mediaURL: URL = try #require(URL(string: "https://video.example.invalid/media/master.m3u8"))
        let pageLoader = RoutedPlaybackPageContentLoader(
            responses: [
                pageURL.absoluteString: PageContentResponse(
                    content: #"<video><source src="/media/master.m3u8"></video>"#,
                    finalURL: pageURL
                )
            ]
        )
        let rule: VideoSiteRule = Self.playbackRule()

        let output: SourceVideoPlaybackOutput = try await VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
        ).execute(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        #expect(output.reference.status == .playable)
        #expect(output.reference.candidateMediaURL == mediaURL)
        #expect(pageLoader.requestedURLs == [pageURL, mediaURL])
    }

    @Test func encryptedHLSRejectsUnobservableWebUIFallback() async throws {
        let pageURL: URL = try #require(URL(string: "https://video.example.invalid/watch/1"))
        let mediaURL: URL = try #require(URL(string: "https://video.example.invalid/media/master.m3u8"))
        let pageLoader = RoutedPlaybackPageContentLoader(
            responses: [
                pageURL.absoluteString: PageContentResponse(
                    content: #"<video><source src="/media/master.m3u8"></video>"#,
                    finalURL: pageURL
                ),
                mediaURL.absoluteString: PageContentResponse(
                    content: "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"https://keys.example.invalid/key\"",
                    finalURL: mediaURL
                )
            ]
        )
        var rule: VideoSiteRule = Self.playbackRule()
        rule.ruleSets.playbackRules?[0].fallback = .webUI
        let loader = VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
        )
        let session: VideoPreparedPlaybackExecutionSession = try loader.prepare(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        let result: VideoPreparedPlaybackExecutionResult = try await loader.executeWithRouteFacts(session)

        #expect(result.output.reference.status == .failed(.unsupportedMediaKind))
        #expect(result.output.reference.candidateMediaURL == nil)
        #expect(result.routeFacts.map(\.routeSlot) == [.media, .fallback])
        #expect(result.routeFacts[0].disposition == .rejectedBeforePlayer)
        #expect(result.routeFacts[0].reason == .encryptedHLS)
        #expect(result.routeFacts[1].disposition == .rejectedBeforePlayer)
        #expect(result.routeFacts[1].reason == .finalMediaObservationUnavailable)
    }

    @Test func encryptedHLSAllowsIndependentDeclaredIframeHLS() async throws {
        let pageURL: URL = try #require(URL(string: "https://video.example.invalid/watch/1"))
        let iframeURL: URL = try #require(URL(string: "https://video.example.invalid/embed/player"))
        let encryptedMediaURL: URL = try #require(URL(string: "https://video.example.invalid/media/master.m3u8"))
        let fallbackMediaURL: URL = try #require(URL(string: "https://video.example.invalid/media/independent.m3u8"))
        let pageLoader = RoutedPlaybackPageContentLoader(
            responses: [
                pageURL.absoluteString: PageContentResponse(
                    content: #"<video><source src="/media/master.m3u8"></video><iframe src="/embed/player"></iframe>"#,
                    finalURL: pageURL
                ),
                encryptedMediaURL.absoluteString: PageContentResponse(
                    content: "#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"skd://asset\"",
                    finalURL: encryptedMediaURL
                ),
                iframeURL.absoluteString: PageContentResponse(
                    content: #"<video><source src="/media/independent.m3u8"></video>"#,
                    finalURL: iframeURL
                ),
                fallbackMediaURL.absoluteString: PageContentResponse(
                    content: "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nsegment.ts",
                    finalURL: fallbackMediaURL
                )
            ]
        )
        var rule: VideoSiteRule = Self.playbackRule()
        rule.ruleSets.playbackRules?[0].iframe = Self.iframeRule(strategy: .resolve, maxDepth: 2)
        let loader = VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
        )
        let session: VideoPreparedPlaybackExecutionSession = try loader.prepare(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        let result: VideoPreparedPlaybackExecutionResult = try await loader.executeWithRouteFacts(session)

        #expect(result.output.reference.status == .playable)
        #expect(result.output.reference.candidateMediaURL == fallbackMediaURL)
        #expect(result.routeFacts.map(\.routeSlot) == [.media, .iframe])
        #expect(result.routeFacts[0].reason == .encryptedHLS)
        #expect(result.routeFacts[1].disposition == .selectedForPlayer)
        #expect(result.routeFacts[1].reason == nil)
        #expect(pageLoader.requestedURLs == [pageURL, encryptedMediaURL, iframeURL, fallbackMediaURL])
    }

    @Test func encryptedHLSRejectsTheSameMediaThroughDeclaredIframe() async throws {
        let pageURL: URL = try #require(URL(string: "https://video.example.invalid/watch/1"))
        let iframeURL: URL = try #require(URL(string: "https://video.example.invalid/embed/player"))
        let mediaURL: URL = try #require(URL(string: "https://video.example.invalid/media/master.m3u8"))
        let pageLoader = RoutedPlaybackPageContentLoader(
            responses: [
                pageURL.absoluteString: PageContentResponse(
                    content: #"<video><source src="/media/master.m3u8"></video><iframe src="/embed/player"></iframe>"#,
                    finalURL: pageURL
                ),
                mediaURL.absoluteString: PageContentResponse(
                    content: "#EXTM3U\n#EXT-X-SESSION-KEY:METHOD=AES-128,URI=\"https://keys.example.invalid/session\"",
                    finalURL: mediaURL
                ),
                iframeURL.absoluteString: PageContentResponse(
                    content: #"<video><source src="/media/master.m3u8"></video>"#,
                    finalURL: iframeURL
                )
            ]
        )
        var rule: VideoSiteRule = Self.playbackRule()
        rule.ruleSets.playbackRules?[0].iframe = Self.iframeRule(strategy: .resolve, maxDepth: 2)
        let loader = VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
        )
        let session: VideoPreparedPlaybackExecutionSession = try loader.prepare(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        let result: VideoPreparedPlaybackExecutionResult = try await loader.executeWithRouteFacts(session)

        #expect(result.output.reference.status == .failed(.unsupportedMediaKind))
        #expect(result.routeFacts.map(\.routeSlot) == [.media, .iframe])
        #expect(result.routeFacts[0].reason == .encryptedHLS)
        #expect(result.routeFacts[1].reason == .knownEncryptedMedia)
        #expect(pageLoader.requestedURLs == [pageURL, mediaURL, iframeURL])
    }
}

private extension VideoSourcePlaybackLoaderTests {
    static func directMediaRule(
        id: String,
        title: String,
        selector: String,
        kind: VideoDirectMediaKind
    ) -> VideoDirectMediaRule {
        VideoDirectMediaRule(
            id: id,
            title: title,
            url: ExtractRule(
                selector: selector,
                selectorKind: .css,
                function: .attr,
                param: "src"
            ),
            kind: kind
        )
    }

    // 中文注释：`BC-EVIDENCE-073`。规则匹配到的广告媒体地址不得进入播放；候选全部被丢弃时
    // 走既有 fallback 语义，且 fallback 的地址是播放页自身，不是被丢弃的地址。
    @Test func advertisingMediaCandidateIsDiscardedAndFallsBackToDeclaredWebUI() async throws {
        let pageURL: URL = try #require(URL(string: "https://video.example.invalid/watch/1"))
        let pageLoader = PlaybackPageContentLoader(
            html: #"<video><source src="https://ads.example.test/ads/preroll/spot.m3u8"></video>"#,
            finalURL: pageURL
        )
        var rule: VideoSiteRule = Self.playbackRule()
        rule.ruleSets.playbackRules?[0].fallback = .webUI
        let loader = VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
        )
        let session: VideoPreparedPlaybackExecutionSession = try loader.prepare(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        let result: VideoPreparedPlaybackExecutionResult = try await loader.executeWithRouteFacts(session)

        #expect(result.output.reference.status == .pageOnly)
        #expect(result.output.reference.candidateMediaKind == .iframePlayer)
        #expect(result.output.reference.candidateMediaURL == pageURL)
        #expect(result.routeFacts.map(\.routeSlot) == [.media, .fallback])
        #expect(result.routeFacts[0].disposition == .rejectedBeforePlayer)
        #expect(result.routeFacts[0].reason == .allCandidatesFilteredAsNoise)
        #expect(result.routeFacts[1].disposition == .selectedForPlayer)
        #expect(
            result.output.diagnostics.issues.contains {
                $0.id == "video.v2.playbackCandidatesFilteredAsNoise"
            }
        )
        #expect(
            result.output.diagnostics.issues.contains {
                $0.message.contains("ads.example.test")
            } == false
        )
    }

    @Test func filteredMediaCandidatesFailWithTheirOwnReasonWhenNoFallbackIsDeclared() async throws {
        let pageLoader = PlaybackPageContentLoader(
            html: #"<video><source src="https://ads.example.test/ads/preroll/spot.m3u8"></video>"#,
            finalURL: try #require(URL(string: "https://video.example.invalid/watch/1"))
        )
        let rule: VideoSiteRule = Self.playbackRule()
        let loader = VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
        )
        let session: VideoPreparedPlaybackExecutionSession = try loader.prepare(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        let result: VideoPreparedPlaybackExecutionResult = try await loader.executeWithRouteFacts(session)

        #expect(result.output.reference.status == .failed(.mediaURLNotFound))
        #expect(result.output.reference.candidateMediaURL == nil)
        #expect(result.routeFacts.map(\.routeSlot) == [.media])
        #expect(result.routeFacts[0].reason == .allCandidatesFilteredAsNoise)
    }

    @Test func unmatchedMediaRuleKeepsNoCandidateReason() async throws {
        let pageLoader = PlaybackPageContentLoader(
            html: "<html><body><p>no media here</p></body></html>",
            finalURL: try #require(URL(string: "https://video.example.invalid/watch/1"))
        )
        let rule: VideoSiteRule = Self.playbackRule()
        let loader = VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
        )
        let session: VideoPreparedPlaybackExecutionSession = try loader.prepare(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        let result: VideoPreparedPlaybackExecutionResult = try await loader.executeWithRouteFacts(session)

        #expect(result.routeFacts[0].reason == .noCandidate)
        #expect(
            result.output.diagnostics.issues.contains {
                $0.id == "video.v2.playbackCandidatesFilteredAsNoise"
            } == false
        )
    }

    @Test func advertisingIframeCandidateIsDiscardedBeforeWebUIHandoff() async throws {
        let pageURL: URL = try #require(URL(string: "https://video.example.invalid/watch/1"))
        let pageLoader = PlaybackPageContentLoader(
            html: #"<iframe src="https://ads.example.test/ads/frame"></iframe>"#,
            finalURL: pageURL
        )
        var rule: VideoSiteRule = Self.playbackRule()
        rule.ruleSets.playbackRules = [
            VideoPlaybackRule(
                id: "playback",
                iframe: Self.iframeRule(strategy: .webUI),
                fallback: .webUI
            )
        ]
        let loader = VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser()
        )
        let session: VideoPreparedPlaybackExecutionSession = try loader.prepare(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        let result: VideoPreparedPlaybackExecutionResult = try await loader.executeWithRouteFacts(session)

        #expect(result.output.reference.status == .pageOnly)
        #expect(result.output.reference.candidateMediaURL == pageURL)
        #expect(result.routeFacts.map(\.routeSlot) == [.iframe, .fallback])
        #expect(result.routeFacts[0].reason == .allCandidatesFilteredAsNoise)
    }

    // 中文注释：`deprioritize` 只改顺序、不丢弃（`BC-EVIDENCE-073`）。当前词表不产生该动作，
    // 因此用注入的过滤器覆盖。
    @Test func deprioritizedCandidateIsKeptButOrderedLast() async throws {
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

        let output: SourceVideoPlaybackOutput = try await VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser(),
            noiseFilter: StubSourceContentNoiseFilter(
                actionsByURLSubstring: ["/media/one.m3u8": .deprioritize]
            )
        ).execute(
            source: Self.source(rule: rule),
            resolvedRule: try ResolvedVideoSiteRule(validating: rule),
            input: Self.input()
        )

        #expect(output.reference.status == .playable)
        #expect(
            output.reference.candidateMediaURL?.absoluteString
                == "https://video.example.invalid/media/two.m3u8"
        )
    }

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

private final class PlaybackPageContentLoader: PageContentLoader {
    let html: String
    let finalURL: URL
    private(set) var lastRequest: RequestConfig?

    init(html: String, finalURL: URL) {
        self.html = html
        self.finalURL = finalURL
    }

    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        self.lastRequest = request.requestConfig
        return PageContentResponse(content: self.html, finalURL: self.finalURL)
    }
}

private final class RoutedPlaybackPageContentLoader: PageContentLoader {
    let responses: [String: PageContentResponse]
    private(set) var requestedURLs: [URL] = []
    private(set) var requests: [PageLoadRequest] = []

    init(responses: [String: PageContentResponse]) {
        self.responses = responses
    }

    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse {
        self.requestedURLs.append(request.url)
        self.requests.append(request)
        guard let response: PageContentResponse = self.responses[request.url.absoluteString] else {
            throw SourceRuntimeError.invalidInput("Missing routed playback response.")
        }
        return response
    }
}

/// 中文注释：只有注入的过滤器才能产生 `deprioritize`——当前词表不会。
private struct StubSourceContentNoiseFilter: SourceContentNoiseFiltering {
    let actionsByURLSubstring: [String: SourceContentNoiseAction]

    func decision(for candidate: SourceContentNoiseCandidate) -> SourceContentNoiseDecision {
        let text: String = candidate.url?.absoluteString ?? ""
        for (substring, action) in self.actionsByURLSubstring where text.contains(substring) {
            return SourceContentNoiseDecision(action: action, reasons: [.advertising])
        }
        return .keep
    }
}
