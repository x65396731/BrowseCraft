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
        let url: URL = try #require(URL(string: "https://video.example.test/watch/sample"))

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
}
