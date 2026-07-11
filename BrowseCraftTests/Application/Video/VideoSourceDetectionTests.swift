import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：普通路由信号只作为事实；强 MacCMS/vfed 信号才会推断内容 mapper。
struct VideoSourceDetectionTests {
    @Test func detectsVideoCMSRouteSignalWithoutChoosingContentMapper() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let url: URL = try #require(URL(string: "https://video.example.test/voddetail/117372.html"))

        let detection: VideoSourceDetection = detector.detect(
            VideoSourceDetectionInput(url: url)
        )

        #expect(detection.adapter == .genericHTML)
        #expect(detection.renderMode == .staticHTML)
        #expect(detection.playbackMode == .unresolved)
        #expect(detection.confidence >= 0.75)
        #expect(detection.reasons.contains { reason in
            reason.contains("Content mapper adapter was not inferred")
        })
    }

    @Test func detectsDirectMediaWithoutChoosingContentMapper() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let url: URL = try #require(URL(string: "https://video.example.test/catalog"))

        let detection: VideoSourceDetection = detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: """
                <html>
                  <body>
                    <article class="video-card">
                      <video><source src="https://media.example.test/sample.m3u8"></video>
                    </article>
                  </body>
                </html>
                """
            )
        )

        #expect(detection.adapter == .genericHTML)
        #expect(detection.renderMode == .staticHTML)
        #expect(detection.playbackMode == .directMedia)
        #expect(detection.confidence >= 0.60)
        #expect(detection.reasons.contains { reason in
            reason.contains("Content mapper adapter was not inferred")
        })
    }

    @Test func detectsStrongVfedMarkersAsMacCMSContentMapper() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let url: URL = try #require(URL(string: "https://video.example.test/"))

        let detection: VideoSourceDetection = detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: """
                <html>
                  <head>
                    <link rel="stylesheet" href="/template/vfed/asset/css/style.css">
                  </head>
                  <body>
                    <script>var vfed = { "tpl": "/template/vfed/" };</script>
                    <ul>
                      <li class="fed-list-item">
                        <a class="fed-list-pics" href="/voddetail/100/"></a>
                        <a class="fed-list-title" href="/voddetail/100/">Title</a>
                      </li>
                    </ul>
                  </body>
                </html>
                """
            )
        )

        #expect(detection.adapter == .macCMS)
        #expect(detection.renderMode == .staticHTML)
        #expect(detection.reasons.contains { reason in
            reason.contains("Strong video CMS markers matched")
        })
    }

    @Test func weakGenericHTMLMarkersAloneDoNotProduceHighConfidence() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let url: URL = try #require(URL(string: "https://video.example.test/"))

        let detection: VideoSourceDetection = detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: """
                <html>
                  <body>
                    <img data-src="/cover.jpg" class="lazyload">
                    <span>播放</span>
                  </body>
                </html>
                """
            )
        )

        #expect(detection.playbackMode == .unresolved)
        #expect(detection.confidence <= 0.36)
    }

    @Test func detectsIframeAsPlaybackLayerNotAdapterLayer() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let url: URL = try #require(URL(string: "https://video.example.test/watch/sample"))

        let detection: VideoSourceDetection = detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: """
                <html>
                  <body>
                    <main class="video-card">
                      <a href="/watch/sample">Sample</a>
                      <iframe src="https://player.example.test/embed/sample"></iframe>
                    </main>
                  </body>
                </html>
                """
            )
        )

        #expect(detection.renderMode == .staticHTML)
        #expect(detection.playbackMode == .iframePlayer)
        #expect(detection.reasons.contains { reason in
            reason.contains("Content mapper adapter was not inferred")
        })
    }

    @Test func framesetShellDoesNotBecomeContentAdapter() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let url: URL = try #require(URL(string: "https://video.example.test/"))

        let detection: VideoSourceDetection = detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: """
                <html>
                  <frameset>
                    <frame src="/video-list.html">
                  </frameset>
                </html>
                """
            )
        )

        #expect(detection.renderMode == .staticHTML)
        #expect(detection.playbackMode == .unresolved)
    }

    @Test func detectsWebViewAsRenderLayerNotAdapterLayer() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let url: URL = try #require(URL(string: "https://video.example.test/"))

        let detection: VideoSourceDetection = detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: """
                <html>
                  <body>
                    <div id="app"></div>
                    <script src="/assets/app.js"></script>
                    <script>window.__INITIAL_STATE__={}</script>
                  </body>
                </html>
                """
            )
        )

        #expect(detection.renderMode == .webViewRequired)
        #expect(detection.playbackMode == .unresolved)
        #expect(detection.warnings.contains { warning in
            warning.contains("Static HTML")
        })
    }

    @Test func detectsSPAShellAsWebViewRequiredWithoutForcingPlugin() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let url: URL = try #require(URL(string: "https://video.example.test/watch/spa"))

        let detection: VideoSourceDetection = detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: """
                <html>
                  <body>
                    <main id="app"></main>
                    <script src="/assets/runtime.js"></script>
                    <script src="/assets/chunk-vendors.js"></script>
                  </body>
                </html>
                """
            )
        )

        #expect(detection.renderMode == .webViewRequired)
        #expect(detection.playbackMode == .unresolved)
        #expect(detection.warnings.contains { warning in
            warning.contains("Static HTML")
        })
    }

    @Test func renderedNextDOMWithVideoCardsIsMappableAfterWebView() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let url: URL = try #require(URL(string: "https://www.arte.tv/en/videos/"))

        let detection: VideoSourceDetection = detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: """
                <html>
                  <head>
                    <script id="__NEXT_DATA__" type="application/json">{}</script>
                  </head>
                  <body>
                    <div id="__next">
                      <article data-testid="video-card">
                        <a href="/en/videos/123456-000-A/european-culture-documentary/">
                          <img src="https://api-cdn.arte.tv/img/v2/image/sample-cover.jpg" alt="European Culture Documentary">
                          <h3>European Culture Documentary</h3>
                        </a>
                      </article>
                    </div>
                  </body>
                </html>
                """
            )
        )

        #expect(detection.renderMode == .staticHTML)
        #expect(detection.adapter == .genericHTML)
        #expect(detection.reasons.contains { reason in
            reason.contains("Content mapper adapter was not inferred")
        })
    }

    @Test func detectsPluginWhenRestrictionSignalsAreStrong() throws {
        let detector: VideoSourceDetector = Self.detector(language: .simplifiedChinese)
        let url: URL = try #require(URL(string: "https://video.example.test/"))

        let detection: VideoSourceDetection = detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: """
                <html>
                  <body>
                    <div>请先登录，会员专享</div>
                    <script>var token = CryptoJS.AES.decrypt(payload, key)</script>
                  </body>
                </html>
                """
            )
        )

        #expect(detection.adapter == .plugin)
        #expect(detection.confidence >= 0.80)
        #expect(detection.warnings.contains { warning in
            warning.contains("account")
        })
    }

    @Test func loginAndVIPMarkersDoNotForcePluginWhenPublicContentExists() throws {
        let detector: VideoSourceDetector = Self.detector(language: .simplifiedChinese)
        let url: URL = try #require(URL(string: "https://video.example.test/"))

        let detection: VideoSourceDetection = detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: """
                <html>
                  <body>
                    <header><a href="/login">登录</a><span>VIP会员</span></header>
                    <article class="video-card thumb-block">
                      <a href="/watch/public-sample">Public Sample</a>
                      <img data-src="/cover.jpg">
                      <span class="duration">12:00</span>
                    </article>
                  </body>
                </html>
                """
            )
        )

        #expect(detection.playbackMode == .unresolved)
        #expect(detection.warnings.contains { warning in
            warning.contains("VIP")
        })
        #expect(detection.warnings.contains { warning in
            warning.contains("login")
        })
    }

    @Test func localizedJapanesePlaybackLabelsOnlyAssistStructureSignals() throws {
        let detector: VideoSourceDetector = Self.detector(language: .japanese)
        let url: URL = try #require(URL(string: "https://jp.example.test/watch/sample"))

        let detection: VideoSourceDetection = detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: """
                <html lang="ja">
                  <body>
                    <article class="thumb-block duration">
                      <a href="/watch/sample">無料サンプルを再生</a>
                      <video>
                        <source src="https://media.example.test/sample.m3u8" type="application/vnd.apple.mpegurl">
                      </video>
                    </article>
                  </body>
                </html>
                """
            )
        )

        #expect(detection.playbackMode == .directMedia)
        #expect(detection.confidence >= 0.70)
    }

    @Test func localizedSemanticMarkersAloneDoNotProduceSupportedConfidence() throws {
        let detector: VideoSourceDetector = Self.detector(language: .japanese)
        let url: URL = try #require(URL(string: "https://jp.example.test/"))

        let detection: VideoSourceDetection = detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: """
                <html lang="ja">
                  <body>
                    <p>ログインしてプレミアム会員エピソードを再生できます。</p>
                  </body>
                </html>
                """
            )
        )

        #expect(detection.playbackMode == .unresolved)
        #expect(detection.confidence <= 0.36)
        #expect(detection.warnings.contains { warning in
            warning.contains("VIP")
        })
        #expect(detection.warnings.contains { warning in
            warning.contains("login")
        })
    }

    @Test func unsupportedSpanishAccountMarkerDoesNotProduceLocalizedLoginWarning() throws {
        let detector: VideoSourceDetector = Self.detector(language: .english)
        let url: URL = try #require(URL(string: "https://es.example.test/"))

        let detection: VideoSourceDetection = detector.detect(
            VideoSourceDetectionInput(
                url: url,
                html: """
                <html lang="es">
                  <body>
                    <header>
                      <a href="/cuenta">Iniciar sesión</a>
                      <span>Premium para miembros</span>
                    </header>
                    <article class="video-card thumb-block duration">
                      <a href="/watch/publico">Ver muestra pública</a>
                      <img data-src="/cover.jpg">
                    </article>
                  </body>
                </html>
                """
            )
        )

        #expect(detection.playbackMode == .unresolved)
        #expect(detection.warnings.contains { warning in
            warning.contains("VIP")
        })
        #expect(detection.warnings.contains { warning in
            warning.contains("login")
        } == false)
    }

    @Test func localizedCaptchaMarkerReportsClosedPluginBoundary() throws {
        let lexicon: VideoDetectionLexicon = Self.videoLexicon(language: .japanese)
        let detector: VideoSourceDetector = VideoSourceDetector(lexicon: lexicon)
        let resolver: VideoSourceImportDecisionResolver = VideoSourceImportDecisionResolver()
        let url: URL = try #require(URL(string: "https://jp.example.test/secure"))
        let definition: VideoSourceDefinition = try Self.videoDefinition(adapter: .plugin, entryURL: url)

        let decision: VideoSourceImportDecision = resolver.decision(
            for: detector.detect(
                VideoSourceDetectionInput(
                    url: url,
                    html: """
                    <html lang="ja">
                      <body>
                        <p>認証コードを確認してください。</p>
                      </body>
                    </html>
                    """
                )
            ),
            definition: definition
        )

        #expect(decision == .unavailable(.pluginBoundaryClosed))
    }

    @Test func importDecisionSupportsHighConfidenceBuiltInVideoSource() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let resolver: VideoSourceImportDecisionResolver = VideoSourceImportDecisionResolver()
        let url: URL = try #require(URL(string: "https://video.example.test/voddetail/117372.html"))
        let definition: VideoSourceDefinition = try Self.videoDefinition(adapter: .macCMS, entryURL: url)

        let decision: VideoSourceImportDecision = resolver.decision(
            for: detector.detect(VideoSourceDetectionInput(url: url)),
            definition: definition
        )

        if case .supported(let supportedDefinition) = decision {
            #expect(supportedDefinition.adapter == .macCMS)
        } else {
            Issue.record("Expected high-confidence video signals with a rule-selected MacCMS adapter to be supported.")
        }
    }

    @Test func importDecisionPromotesStrongVfedGenericHTMLDefinitionToMacCMS() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let resolver: VideoSourceImportDecisionResolver = VideoSourceImportDecisionResolver()
        let url: URL = try #require(URL(string: "https://video.example.test/"))
        let definition: VideoSourceDefinition = try Self.videoDefinition(adapter: .genericHTML, entryURL: url)

        let decision: VideoSourceImportDecision = resolver.decision(
            for: detector.detect(
                VideoSourceDetectionInput(
                    url: url,
                    html: """
                    <html>
                      <head>
                        <link rel="stylesheet" href="/template/vfed/asset/css/style.css">
                      </head>
                      <body>
                        <script>var vfed = { "tpl": "/template/vfed/" };</script>
                        <div class="fed-list-item">
                          <a class="fed-list-pics" href="/voddetail/100/"></a>
                          <a class="fed-list-title" href="/voddetail/100/">Title</a>
                          <a class="fed-play-item" href="/vodplay/100-1-1/">Play</a>
                        </div>
                      </body>
                    </html>
                    """
                )
            ),
            definition: definition
        )

        if case .supported(let supportedDefinition) = decision {
            #expect(supportedDefinition.adapter == .macCMS)
            #expect(supportedDefinition.routePatterns == .macCMS)
        } else {
            Issue.record("Expected strong vfed signals to promote a Generic HTML definition to MacCMS.")
        }
    }

    @Test func importDecisionUsesNeedsReviewForMediumConfidenceGenericHTML() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let resolver: VideoSourceImportDecisionResolver = VideoSourceImportDecisionResolver()
        let url: URL = try #require(URL(string: "https://video.example.test/watch/sample"))
        let definition: VideoSourceDefinition = try Self.videoDefinition(adapter: .genericHTML, entryURL: url)

        let decision: VideoSourceImportDecision = resolver.decision(
            for: detector.detect(
                VideoSourceDetectionInput(
                    url: url,
                    html: """
                    <html>
                      <body>
                        <article class="video-card thumb-block duration thumbnail">
                          <a href="/watch/a">A</a>
                          <a href="/watch/b">B</a>
                        </article>
                      </body>
                    </html>
                    """
                )
            ),
            definition: definition
        )

        if case .needsReview(let reviewDefinition, _) = decision {
            #expect(reviewDefinition.adapter == .genericHTML)
        } else {
            Issue.record("Expected medium-confidence video signals with a rule-selected Generic HTML adapter to need review.")
        }
    }

    @Test func importDecisionDoesNotTreatNoVideoSignalsAsPlugin() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let resolver: VideoSourceImportDecisionResolver = VideoSourceImportDecisionResolver()
        let url: URL = try #require(URL(string: "https://article.example.test/about"))
        let definition: VideoSourceDefinition = try Self.videoDefinition(adapter: .genericHTML, entryURL: url)

        let decision: VideoSourceImportDecision = resolver.decision(
            for: detector.detect(
                VideoSourceDetectionInput(
                    url: url,
                    html: """
                    <html>
                      <body>
                        <h1>About this site</h1>
                        <p>Company profile and contact information.</p>
                      </body>
                    </html>
                    """
                )
            ),
            definition: definition
        )

        #expect(decision == .unavailable(.noVideoSignals))
    }

    @Test func importDecisionTreatsLowConfidenceAsUnavailableNotPlugin() throws {
        let resolver: VideoSourceImportDecisionResolver = VideoSourceImportDecisionResolver()
        let url: URL = try #require(URL(string: "https://video.example.test/watch/weak"))
        let definition: VideoSourceDefinition = try Self.videoDefinition(adapter: .genericHTML, entryURL: url)

        let decision: VideoSourceImportDecision = resolver.decision(
            for: VideoSourceDetection(
                adapter: .genericHTML,
                renderMode: .staticHTML,
                playbackMode: .unresolved,
                confidence: 0.42,
                reasons: ["Generic video signal exists, but confidence is below review threshold."],
                warnings: []
            ),
            definition: definition
        )

        #expect(decision == .unavailable(.lowConfidence))
    }

    @Test func accountWarningDoesNotBypassClosedPluginBoundary() throws {
        let resolver: VideoSourceImportDecisionResolver = VideoSourceImportDecisionResolver()
        let url: URL = try #require(URL(string: "https://video.example.test/secure"))
        let definition: VideoSourceDefinition = try Self.videoDefinition(adapter: .plugin, entryURL: url)

        let decision: VideoSourceImportDecision = resolver.decision(
            for: VideoSourceDetection(
                adapter: .plugin,
                renderMode: .staticHTML,
                playbackMode: .unresolved,
                confidence: 0.82,
                reasons: ["HTML contains plugin-level markers: custom private runtime."],
                warnings: ["The page contains login markers."]
            ),
            definition: definition
        )

        #expect(decision == .unavailable(.pluginBoundaryClosed))
    }

    @Test func importDecisionRoutesWebViewRequiredToNeedsReviewWithRenderedDOMRequest() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let resolver: VideoSourceImportDecisionResolver = VideoSourceImportDecisionResolver()
        let url: URL = try #require(URL(string: "https://video.example.test/watch/spa"))
        let definition: VideoSourceDefinition = try Self.videoDefinition(adapter: .genericHTML, entryURL: url)

        let decision: VideoSourceImportDecision = resolver.decision(
            for: detector.detect(
                VideoSourceDetectionInput(
                    url: url,
                    html: """
                    <html>
                      <body>
                        <main id="app"></main>
                        <script src="/assets/runtime.js"></script>
                      </body>
                    </html>
                    """
                )
            ),
            definition: definition
        )

        if case .needsReview(let reviewDefinition, let warnings) = decision {
            #expect(reviewDefinition.adapter == .genericHTML)
            #expect(reviewDefinition.sharedRequest?.needsWebView == true)
            #expect(warnings.contains { warning in
                warning.contains("WebView-rendered DOM")
            })
        } else {
            Issue.record("Expected WebView-required source to stay in built-in review path.")
        }
    }

    @Test func importDecisionTreatsEncryptedPlaybackAsClosedPluginBoundary() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let resolver: VideoSourceImportDecisionResolver = VideoSourceImportDecisionResolver()
        let url: URL = try #require(URL(string: "https://video.example.test/secure"))
        let definition: VideoSourceDefinition = try Self.videoDefinition(adapter: .plugin, entryURL: url)

        let decision: VideoSourceImportDecision = resolver.decision(
            for: detector.detect(
                VideoSourceDetectionInput(
                    url: url,
                    html: """
                    <html>
                      <body>
                        <script>var media = CryptoJS.AES.decrypt(payload, key)</script>
                      </body>
                    </html>
                    """
                )
            ),
            definition: definition
        )

        #expect(decision == .unavailable(.pluginBoundaryClosed))
    }

    @Test func legacyVideoAdapterDetectorWrapsFactDetectionWithoutChoosingMapper() throws {
        let detector: VideoAdapterDetector = VideoAdapterDetector()
        let url: URL = try #require(URL(string: "https://video.example.test/watch/sample"))

        let detection: VideoAdapterDetection = detector.detect(
            VideoAdapterDetectionInput(
                url: url,
                html: """
                <html>
                  <body>
                    <video src="https://media.example.test/sample.mp4"></video>
                  </body>
                </html>
                """
            )
        )

        #expect(detection.adapter == .genericHTML)
        #expect(detection.reasons.contains { reason in
            reason.contains("Render mode")
        })
        #expect(detection.reasons.contains { reason in
            reason.contains("Playback mode")
        })
        #expect(detection.reasons.contains { reason in
            reason.contains("Content mapper adapter was not inferred")
        })
    }

    private static func detector(language: SourceDetectionLexicon.Language) -> VideoSourceDetector {
        return VideoSourceDetector(lexicon: Self.videoLexicon(language: language))
    }

    private static func videoLexicon(language: SourceDetectionLexicon.Language) -> VideoDetectionLexicon {
        return VideoDetectionLexicon(
            sourceLexicon: SourceDetectionLexicon.load(language: language)
        )
    }

    private static func videoDefinition(
        adapter: VideoAdapter,
        entryURL: URL
    ) throws -> VideoSourceDefinition {
        return VideoSourceDefinition(
            adapter: adapter,
            entryURL: entryURL,
            seedURL: nil,
            entryKind: .home,
            routePatterns: adapter == .macCMS ? .macCMS : nil,
            playbackPolicy: .playPageFirst,
            requiresAccount: false,
            seedVodID: nil,
            seedSourceIndex: nil,
            seedEpisodeIndex: nil,
            seedDetailURL: nil,
            seedPlayURL: nil
        )
    }
}
