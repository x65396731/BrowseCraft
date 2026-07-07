import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：P5.1.9 固定视频源检测三层模型，避免 adapter、render、playback 混成一个分类。
struct VideoSourceDetectionTests {
    @Test func detectsMacCMSAdapterFromRouteSignal() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let url: URL = try #require(URL(string: "https://video.example.test/voddetail/117372.html"))

        let detection: VideoSourceDetection = detector.detect(
            VideoSourceDetectionInput(url: url)
        )

        #expect(detection.adapter == .macCMS)
        #expect(detection.renderMode == .staticHTML)
        #expect(detection.playbackMode == .unresolved)
        #expect(detection.confidence >= 0.75)
    }

    @Test func detectsGenericHTMLDirectMediaWithoutWeakMarkerDependence() throws {
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

        #expect(detection.adapter == .genericHTML)
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

        #expect(detection.adapter == .genericHTML)
        #expect(detection.renderMode == .staticHTML)
        #expect(detection.playbackMode == .iframe)
    }

    @Test func detectsIframeAsContentAdapterWhenItIsTheMainContentShell() throws {
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

        #expect(detection.adapter == .iframe)
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

        #expect(detection.adapter == .genericHTML)
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

        #expect(detection.adapter == .genericHTML)
        #expect(detection.renderMode == .webViewRequired)
        #expect(detection.playbackMode == .unresolved)
        #expect(detection.warnings.contains { warning in
            warning.contains("Static HTML")
        })
    }

    @Test func detectsPluginWhenRestrictionSignalsAreStrong() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
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
        let detector: VideoSourceDetector = VideoSourceDetector()
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

        #expect(detection.adapter == .genericHTML)
        #expect(detection.playbackMode == .unresolved)
        #expect(detection.warnings.contains { warning in
            warning.contains("VIP")
        })
        #expect(detection.warnings.contains { warning in
            warning.contains("login")
        })
    }

    @Test func localizedJapanesePlaybackLabelsOnlyAssistStructureSignals() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
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

        #expect(detection.adapter == .genericHTML)
        #expect(detection.playbackMode == .directMedia)
        #expect(detection.confidence >= 0.70)
    }

    @Test func localizedSemanticMarkersAloneDoNotProduceSupportedConfidence() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
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

        #expect(detection.adapter == .genericHTML)
        #expect(detection.playbackMode == .unresolved)
        #expect(detection.confidence <= 0.36)
        #expect(detection.warnings.contains { warning in
            warning.contains("VIP")
        })
        #expect(detection.warnings.contains { warning in
            warning.contains("login")
        })
    }

    @Test func spanishAccountAndPayMarkersDoNotForcePluginWhenPublicContentExists() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
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

        #expect(detection.adapter == .genericHTML)
        #expect(detection.playbackMode == .unresolved)
        #expect(detection.warnings.contains { warning in
            warning.contains("VIP")
        })
        #expect(detection.warnings.contains { warning in
            warning.contains("login")
        })
    }

    @Test func localizedCaptchaMarkerStillRoutesToPluginBoundary() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
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

        #expect(decision == .pluginRequired(.captchaOrAntiBot))
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
            Issue.record("Expected high-confidence MacCMS detection to be supported.")
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
            Issue.record("Expected medium-confidence generic HTML detection to need review.")
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

    @Test func importDecisionRoutesWebViewRequiredToUnavailable() throws {
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

        #expect(decision == .unavailable(.webViewNotConnected))
    }

    @Test func importDecisionRoutesIframeContentAdapterToUnavailable() throws {
        let detector: VideoSourceDetector = VideoSourceDetector()
        let resolver: VideoSourceImportDecisionResolver = VideoSourceImportDecisionResolver()
        let url: URL = try #require(URL(string: "https://video.example.test/"))
        let definition: VideoSourceDefinition = try Self.videoDefinition(adapter: .iframe, entryURL: url)

        let decision: VideoSourceImportDecision = resolver.decision(
            for: detector.detect(
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
            ),
            definition: definition
        )

        #expect(decision == .unavailable(.iframeContentNotConnected))
    }

    @Test func importDecisionRoutesEncryptedPlaybackToPluginRequired() throws {
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

        #expect(decision == .pluginRequired(.encryptedPlayback))
    }

    @Test func legacyVideoAdapterDetectorWrapsThreeLayerDetection() throws {
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
