import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：P5.1.7 使用真实 genericHTML 样本固定静态 HTML 和播放器脚本解析，不验证媒体 URL 长期可播放。
struct VideoRuntimeGenericHTMLMappingTests {
    @Test func genericHTMLMapperExtractsXVideosLikeListItems() throws {
        let mapper: any VideoContentMapper = VideoContentMapperRegistry().mapper(for: .genericHTML)
        let definition: SourceDefinition = try Self.videoDefinition()
        let listURL: URL = try #require(URL(string: "https://www.xvideos.com/"))

        let items: [SourceContentItem] = try mapper.mapList(
            html: Self.fixture(named: "xvideos-home"),
            definition: definition,
            pageURL: listURL
        )

        #expect(items.count >= 10)
        #expect(items.allSatisfy { item in
            return item.title.isEmpty == false
                && item.detailURL?.host == "www.xvideos.com"
        })
        #expect(items.contains { item in
            return item.coverURL != nil && item.latestText?.contains("min") == true
        })
    }

    @Test func genericHTMLMapperFiltersObviousNoiseListItems() throws {
        let mapper: GenericHTMLVideoContentMapper = GenericHTMLVideoContentMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let listURL: URL = try #require(URL(string: "https://video.example.test/"))

        let items: [SourceContentItem] = try mapper.mapList(
            html: """
            <html>
              <body>
                <article class="video-card ad-banner sponsored">
                  <a href="/promo/install-app">Sponsored Install App</a>
                  <img src="/promo.jpg" alt="Sponsored Install App">
                </article>
                <article class="video-card">
                  <a href="/watch/movie-1" title="Movie 1">Movie 1</a>
                  <img src="/movie-1.jpg" alt="Movie 1">
                  <span class="duration">12 min</span>
                </article>
              </body>
            </html>
            """,
            definition: definition,
            pageURL: listURL
        )

        #expect(items.count == 1)
        #expect(items.first?.title == "Movie 1")
        #expect(items.first?.detailURL?.absoluteString == "https://video.example.test/watch/movie-1")
    }

    @Test func genericHTMLMapperBuildsDetailContentFromPlayablePage() throws {
        let mapper: any VideoContentMapper = VideoContentMapperRegistry().mapper(for: .genericHTML)
        let definition: SourceDefinition = try Self.videoDefinition()
        let detailURL: URL = try #require(URL(string: "https://www.xvideos.com/video.opiftaofe66/49155991/0/amateur_coed_gets_fucked_before_party_-_daisy_fox"))

        let detail: VideoDetailContent = try mapper.mapDetail(
            html: Self.fixture(named: "xvideos-detail"),
            definition: definition,
            detailURL: detailURL
        )

        #expect(detail.episodes.isEmpty == false)
        #expect(detail.episodes.contains { episode in
            return episode.playPageURL.host == "www.xvideos.com"
                || episode.playPageURL.absoluteString.contains(".mp4")
        })
    }

    @Test func genericHTMLMapperExtractsARTEWebViewRenderedListItems() throws {
        let mapper: GenericHTMLVideoContentMapper = GenericHTMLVideoContentMapper()
        let definition: SourceDefinition = try Self.arteVideoDefinition(
            sharedRequest: RequestConfig(needsWebView: true, autoScroll: true)
        )
        let listURL: URL = try #require(URL(string: "https://www.arte.tv/en/videos/"))

        let items: [SourceContentItem] = try mapper.mapList(
            html: Self.fixture(named: "arte-rendered-list"),
            definition: definition,
            pageURL: listURL
        )

        #expect(items.count == 2)
        #expect(items[0].title == "European Culture Documentary")
        #expect(items[0].detailURL?.absoluteString == "https://www.arte.tv/en/videos/123456-000-A/european-culture-documentary/")
        #expect(items[0].coverURL?.host == "api-cdn.arte.tv")
        #expect(items[0].latestText == "Documentary - 52 min")
    }

    @Test func genericHTMLMapperExtractsListCoverFromSrcset() throws {
        let mapper: GenericHTMLVideoContentMapper = GenericHTMLVideoContentMapper()
        let definition: SourceDefinition = try Self.arteVideoDefinition(
            sharedRequest: RequestConfig(needsWebView: true, autoScroll: true)
        )
        let listURL: URL = try #require(URL(string: "https://www.arte.tv/en/videos/"))

        let items: [SourceContentItem] = try mapper.mapList(
            html: """
            <html>
              <body>
                <article data-testid="video-card">
                  <a href="/en/videos/115289-000-A/arte-reportage/" title="ARTE Reportage">
                    <picture>
                      <source srcset="https://api-cdn.arte.tv/img/v2/image/reportage-640.jpg 640w, https://api-cdn.arte.tv/img/v2/image/reportage-1280.jpg 1280w">
                      <img alt="ARTE Reportage">
                    </picture>
                  </a>
                  <span class="metadata">Reportage - 24 min</span>
                </article>
              </body>
            </html>
            """,
            definition: definition,
            pageURL: listURL
        )

        #expect(items.count == 1)
        #expect(items[0].coverURL?.absoluteString == "https://api-cdn.arte.tv/img/v2/image/reportage-640.jpg")
    }

    @Test func genericHTMLMapperBackfillsARTECoverFromRenderedPageData() throws {
        let mapper: GenericHTMLVideoContentMapper = GenericHTMLVideoContentMapper()
        let definition: SourceDefinition = try Self.arteVideoDefinition(
            sharedRequest: RequestConfig(needsWebView: true, autoScroll: true)
        )
        let listURL: URL = try #require(URL(string: "https://www.arte.tv/en/videos/"))

        let items: [SourceContentItem] = try mapper.mapList(
            html: """
            <html>
              <body>
                <article data-testid="video-card">
                  <a href="/en/videos/RC-024146/duels-of-history/" title="Duels of History">
                    Duels of History
                  </a>
                </article>
                <script id="__NEXT_DATA__" type="application/json">
                  {
                    "href": "https:\\/\\/www.arte.tv\\/en\\/videos\\/RC-024146\\/duels-of-history\\/",
                    "image": "https:\\/\\/api-cdn.arte.tv\\/img\\/v2\\/image\\/duels-cover\\/620x350?type=TEXT"
                  }
                </script>
              </body>
            </html>
            """,
            definition: definition,
            pageURL: listURL
        )

        #expect(items.count == 1)
        #expect(items[0].coverURL?.absoluteString == "https://api-cdn.arte.tv/img/v2/image/duels-cover/620x350?type=TEXT")
    }

    @Test func genericHTMLMapperSkipsARTELanguageSwitchItems() throws {
        let mapper: GenericHTMLVideoContentMapper = GenericHTMLVideoContentMapper()
        let definition: SourceDefinition = try Self.arteVideoDefinition(
            sharedRequest: RequestConfig(needsWebView: true, autoScroll: true)
        )
        let listURL: URL = try #require(URL(string: "https://www.arte.tv/en/videos/cinema/"))

        let items: [SourceContentItem] = try mapper.mapList(
            html: """
            <html>
              <body>
                <article>
                  <a href="/fr/videos/cinema/" title="Français (FR)">Français (FR)</a>
                </article>
                <article>
                  <a href="/en/videos/cinema/" title="English (EN)">English (EN)</a>
                </article>
                <article data-testid="video-card">
                  <a href="/en/videos/132676-000-A/raye-guests/" title="RAYE | Guests">RAYE | Guests</a>
                  <img src="https://api-cdn.arte.tv/img/v2/image/raye/620x350?type=TEXT" alt="RAYE | Guests">
                </article>
              </body>
            </html>
            """,
            definition: definition,
            pageURL: listURL
        )

        #expect(items.count == 1)
        #expect(items.first?.title == "RAYE | Guests")
    }

    @Test func genericHTMLMapperExtractsHTML5PlayerPlaybackURL() throws {
        let mapper: any VideoContentMapper = VideoContentMapperRegistry().mapper(for: .genericHTML)
        let definition: SourceDefinition = try Self.videoDefinition()
        let playURL: URL = try #require(URL(string: "https://www.xvideos.com/video.opiftaofe66/49155991/0/amateur_coed_gets_fucked_before_party_-_daisy_fox"))

        let playback: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: Self.fixture(named: "xvideos-detail"),
            definition: definition,
            playPageURL: playURL
        )

        #expect(playback.vodID == "video.opiftaofe66-49155991-0-amateur_coed_gets_fucked_before_party_-_daisy_fox")
        #expect(playback.candidateMediaKind == .m3u8)
        #expect(playback.candidateMediaURL?.absoluteString.contains(".m3u8") == true)
        #expect(playback.status == .playable)
        #expect(playback.playbackRequestConfig?.headers["Referer"] == playURL.absoluteString)
        #expect(playback.sourceName == "genericHTML")
    }

    @Test func genericHTMLMapperFallsBackToJSONLDContentURL() throws {
        let mapper: GenericHTMLVideoContentMapper = GenericHTMLVideoContentMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let playURL: URL = try #require(URL(string: "https://video.example.test/watch/sample"))

        let playback: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: """
            <html>
              <head>
                <script type="application/ld+json">
                  {"@type":"VideoObject","contentUrl":"https://media.example.test/video/sample.mp4"}
                </script>
              </head>
              <body><h1>Sample Video</h1></body>
            </html>
            """,
            definition: definition,
            playPageURL: playURL
        )

        #expect(playback.candidateMediaURL?.absoluteString == "https://media.example.test/video/sample.mp4")
        #expect(playback.candidateMediaKind == .mp4)
        #expect(playback.status == .playable)
    }

    @Test func genericHTMLMapperClassifiesIframeAsPageOnly() throws {
        let mapper: GenericHTMLVideoContentMapper = GenericHTMLVideoContentMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let playURL: URL = try #require(URL(string: "https://video.example.test/watch/iframe"))

        let playback: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: """
            <html>
              <body>
                <iframe src="https://player.example.test/embed/sample"></iframe>
              </body>
            </html>
            """,
            definition: definition,
            playPageURL: playURL
        )

        #expect(playback.candidateMediaKind == .iframePlayer)
        #expect(playback.status == .pageOnly)
    }

    @Test func genericHTMLMapperKeepsRenderedWebViewPlaybackPageOpenWhenDirectMediaIsHidden() throws {
        let mapper: GenericHTMLVideoContentMapper = GenericHTMLVideoContentMapper()
        let definition: SourceDefinition = try Self.arteVideoDefinition(
            sharedRequest: RequestConfig(needsWebView: true, autoScroll: true)
        )
        let playURL: URL = try #require(URL(string: "https://www.arte.tv/en/videos/RC-024169/arte-book-club/"))

        let playback: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: """
            <html>
              <head>
                <script id="__NEXT_DATA__" type="application/json">
                  {"props":{"pageProps":{"programId":"RC-024169"}}}
                </script>
              </head>
              <body>
                <main>
                  <h1>ARTE Book Club</h1>
                  <div data-testid="video-player"></div>
                </main>
              </body>
            </html>
            """,
            definition: definition,
            playPageURL: playURL
        )

        #expect(playback.candidateMediaURL == nil)
        #expect(playback.candidateMediaKind == .unknown)
        #expect(playback.status == .pageOnly)
    }

    @Test func genericHTMLMapperResolvesRelativeIframePlaybackURL() throws {
        let mapper: GenericHTMLVideoContentMapper = GenericHTMLVideoContentMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let playURL: URL = try #require(URL(string: "https://video.example.test/watch/iframe"))

        let playback: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: """
            <html>
              <body>
                <iframe src="/embed/sample" allowfullscreen></iframe>
              </body>
            </html>
            """,
            definition: definition,
            playPageURL: playURL
        )

        #expect(playback.candidateMediaURL?.absoluteString == "https://video.example.test/embed/sample")
        #expect(playback.candidateMediaKind == .iframePlayer)
        #expect(playback.status == .pageOnly)
        #expect(playback.playbackRequestConfig?.referer == playURL)
    }

    @Test func genericHTMLMapperSkipsTrackingIframeBeforePlaybackIframe() throws {
        let mapper: GenericHTMLVideoContentMapper = GenericHTMLVideoContentMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let playURL: URL = try #require(URL(string: "https://video.example.test/watch/iframe"))

        let playback: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: """
            <html>
              <body>
                <iframe class="tracking-pixel" src="https://analytics.example.test/pixel"></iframe>
                <iframe class="responsive-player" src="/embed/movie-1" allowfullscreen></iframe>
              </body>
            </html>
            """,
            definition: definition,
            playPageURL: playURL
        )

        #expect(playback.candidateMediaURL?.absoluteString == "https://video.example.test/embed/movie-1")
        #expect(playback.candidateMediaKind == .iframePlayer)
        #expect(playback.status == .pageOnly)
    }

    @Test func videoListLoaderRejectsStaticWebViewShellBeforeContentMapping() async throws {
        let loader: VideoSourceListLoader = VideoSourceListLoader(
            pageContentLoader: RecordingVideoPageContentLoader(html: Self.webViewShellHTML),
            mapper: GenericHTMLVideoContentMapper()
        )
        let definition: SourceDefinition = try Self.videoDefinition()

        do {
            _ = try await loader.loadList(
                SourceListInput(
                    page: 1,
                    urlOverride: nil,
                    context: Self.context(sourceID: definition.id, operation: .list)
                ),
                definition: definition
            )
            Issue.record("Expected static WebView shell HTML to be rejected before content mapping.")
        } catch SourceRuntimeError.unsupported(.custom(let message)) {
            #expect(message.contains("WebView-rendered DOM"))
            #expect(message.contains("webViewRequired"))
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func videoPlaybackLoaderRejectsStaticWebViewShellBeforeContentMapping() async throws {
        let loader: VideoSourcePlaybackLoader = VideoSourcePlaybackLoader(
            pageContentLoader: RecordingVideoPageContentLoader(html: Self.webViewShellHTML),
            mapper: GenericHTMLVideoContentMapper()
        )
        let definition: SourceDefinition = try Self.videoDefinition()
        let playURL: URL = try #require(URL(string: "https://www.xvideos.com/watch/spa"))

        do {
            _ = try await loader.loadPlayback(
                SourceVideoPlaybackInput(
                    playPageURL: playURL,
                    context: Self.context(sourceID: definition.id, operation: .reader)
                ),
                definition: definition
            )
            Issue.record("Expected static WebView shell playback HTML to be rejected before content mapping.")
        } catch SourceRuntimeError.unsupported(.custom(let message)) {
            #expect(message.contains("WebView-rendered DOM"))
            #expect(message.contains("webViewRequired"))
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func videoListLoaderUsesWebViewRequestAndReportsRenderedDOM() async throws {
        let pageLoader: RecordingVideoPageContentLoader = RecordingVideoPageContentLoader(
            html: Self.renderedListHTML
        )
        let loader: VideoSourceListLoader = VideoSourceListLoader(
            pageContentLoader: pageLoader,
            mapper: GenericHTMLVideoContentMapper()
        )
        let definition: SourceDefinition = try Self.videoDefinition(
            listRequest: RequestConfig(needsWebView: true)
        )

        let output: SourceListOutput = try await loader.loadList(
            SourceListInput(
                page: 1,
                urlOverride: nil,
                context: Self.context(sourceID: definition.id, operation: .list)
            ),
            definition: definition
        )

        #expect(pageLoader.lastRequest?.needsWebView == true)
        #expect(output.items.count == 1)
        #expect(output.diagnostics.issues.contains { issue in
            issue.id == "video.webViewRenderedDOMUsed"
        })
    }

    @Test func videoListLoaderMapsARTEWebViewRenderedDOMWithNextShell() async throws {
        let pageLoader: RecordingVideoPageContentLoader = RecordingVideoPageContentLoader(
            html: try Self.fixture(named: "arte-rendered-list")
        )
        let loader: VideoSourceListLoader = VideoSourceListLoader(
            pageContentLoader: pageLoader,
            mapper: GenericHTMLVideoContentMapper()
        )
        let definition: SourceDefinition = try Self.arteVideoDefinition(
            sharedRequest: RequestConfig(needsWebView: true, autoScroll: true)
        )

        let output: SourceListOutput = try await loader.loadList(
            SourceListInput(
                page: 1,
                urlOverride: nil,
                context: Self.context(sourceID: definition.id, operation: .list)
            ),
            definition: definition
        )

        #expect(pageLoader.lastRequest?.needsWebView == true)
        #expect(pageLoader.lastRequest?.autoScroll == true)
        #expect(output.items.map(\.title) == [
            "European Culture Documentary",
            "Jazz Concert Live"
        ])
        #expect(output.diagnostics.issues.contains { issue in
            issue.id == "video.webViewRenderedDOMUsed"
        })
        #expect(output.diagnostics.issues.contains { issue in
            issue.id == "video.selectorEmpty"
        } == false)
    }

    @Test func videoDetailLoaderUsesStageWebViewRequest() async throws {
        let pageLoader: RecordingVideoPageContentLoader = RecordingVideoPageContentLoader(
            html: Self.renderedDetailHTML
        )
        let loader: VideoSourceDetailLoader = VideoSourceDetailLoader(
            pageContentLoader: pageLoader,
            mapper: GenericHTMLVideoContentMapper()
        )
        let definition: SourceDefinition = try Self.videoDefinition(
            detailRequest: RequestConfig(needsWebView: true)
        )
        let detailURL: URL = try #require(URL(string: "https://www.xvideos.com/watch/movie-1"))

        let content: VideoDetailContent = try await loader.loadDetailContent(
            SourceDetailInput(
                detailURL: detailURL,
                context: Self.context(sourceID: definition.id, operation: .detail)
            ),
            definition: definition
        )

        #expect(pageLoader.lastRequest?.needsWebView == true)
        #expect(content.episodes.count == 1)
        #expect(content.issues.contains { issue in
            issue.id == "video.webViewRenderedDOMUsed"
        })
    }

    @Test func videoPlaybackLoaderUsesOverrideWebViewRequest() async throws {
        let pageLoader: RecordingVideoPageContentLoader = RecordingVideoPageContentLoader(
            html: Self.renderedPlaybackHTML
        )
        let loader: VideoSourcePlaybackLoader = VideoSourcePlaybackLoader(
            pageContentLoader: pageLoader,
            mapper: GenericHTMLVideoContentMapper()
        )
        let definition: SourceDefinition = try Self.videoDefinition(
            playRequest: RequestConfig(needsWebView: false)
        )
        let playURL: URL = try #require(URL(string: "https://www.xvideos.com/watch/movie-1"))

        let output: SourceVideoPlaybackOutput = try await loader.loadPlayback(
            SourceVideoPlaybackInput(
                playPageURL: playURL,
                context: Self.context(
                    sourceID: definition.id,
                    operation: .reader,
                    requestOverride: SourceRequestOverride(
                        url: nil,
                        headers: [:],
                        requiresWebView: true
                    )
                )
            ),
            definition: definition
        )

        #expect(pageLoader.lastRequest?.needsWebView == true)
        #expect(output.reference.status == .playable)
        #expect(output.diagnostics.issues.contains { issue in
            issue.id == "video.webViewRenderedDOMUsed"
        })
    }

    @Test func videoListLoaderRejectsWebViewRenderedShell() async throws {
        let loader: VideoSourceListLoader = VideoSourceListLoader(
            pageContentLoader: RecordingVideoPageContentLoader(html: Self.webViewShellHTML),
            mapper: GenericHTMLVideoContentMapper()
        )
        let definition: SourceDefinition = try Self.videoDefinition(
            listRequest: RequestConfig(needsWebView: true)
        )

        do {
            _ = try await loader.loadList(
                SourceListInput(
                    page: 1,
                    urlOverride: nil,
                    context: Self.context(sourceID: definition.id, operation: .list)
                ),
                definition: definition
            )
            Issue.record("Expected WebView-rendered shell HTML to be rejected.")
        } catch SourceRuntimeError.unsupported(.custom(let message)) {
            #expect(message.contains("video.renderedHTMLStillShell"))
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func webViewAdapterUsesGenericContentMapperAsLegacyRenderSignal() throws {
        let registry: VideoContentMapperRegistry = VideoContentMapperRegistry()
        let mapper: any VideoContentMapper = registry.mapper(for: .webView)
        let definition: SourceDefinition = try Self.videoDefinition()
        let url: URL = try #require(URL(string: "https://video.example.test/"))

        let items: [SourceContentItem] = try mapper.mapList(
            html: """
            <html>
              <body>
                <article class="video-card">
                  <a href="/watch/movie-1" title="Movie 1">Movie 1</a>
                </article>
              </body>
            </html>
            """,
            definition: definition,
            pageURL: url
        )

        #expect(items.count == 1)
    }

    @Test func pluginAdapterReportsPluginModuleBranch() throws {
        let registry: VideoContentMapperRegistry = VideoContentMapperRegistry()
        let definition: SourceDefinition = try Self.videoDefinition()
        let url: URL = try #require(URL(string: "https://video.example.test/"))

        do {
            _ = try registry.mapper(for: .plugin).mapList(
                html: "<html></html>",
                definition: definition,
                pageURL: url
            )
            Issue.record("Expected plugin adapter to report Plugin module branch.")
        } catch SourceRuntimeError.unsupported(.custom(let message)) {
            #expect(message.contains("Plugin module"))
            #expect(message.contains("PluginSourceRuntime"))
        } catch {
            Issue.record("Unexpected plugin adapter error: \(error.localizedDescription)")
        }
    }

    private static func fixture(named name: String) throws -> String {
        let fileURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Video")
            .appendingPathComponent("GenericHTML")
            .appendingPathComponent("\(name).html")

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private static var webViewShellHTML: String {
        return """
        <html>
          <body>
            <main id="app"></main>
            <script src="/assets/runtime.js"></script>
            <script src="/assets/chunk-vendors.js"></script>
          </body>
        </html>
        """
    }

    private static var renderedListHTML: String {
        return """
        <html>
          <body>
            <article class="video-card">
              <a href="/watch/movie-1" title="Movie 1">Movie 1</a>
              <img src="/movie-1.jpg" alt="Movie 1">
            </article>
          </body>
        </html>
        """
    }

    private static var renderedDetailHTML: String {
        return """
        <html>
          <body>
            <h1>Movie 1</h1>
            <p class="description">A rendered detail page with enough description text for mapping.</p>
          </body>
        </html>
        """
    }

    private static var renderedPlaybackHTML: String {
        return """
        <html>
          <body>
            <video>
              <source src="https://media.example.test/movie-1.m3u8">
            </video>
          </body>
        </html>
        """
    }

    private static func context(
        sourceID: String,
        operation: SourceRuntimeOperation,
        requestOverride: SourceRequestOverride? = nil
    ) -> SourceRuntimeContext {
        return SourceRuntimeContext(
            sourceID: sourceID,
            pageID: nil,
            tabID: nil,
            ruleID: nil,
            requestOverride: requestOverride,
            debugMode: false,
            operation: operation
        )
    }

    private static func videoDefinition(
        sharedRequest: RequestConfig? = nil,
        listRequest: RequestConfig? = nil,
        detailRequest: RequestConfig? = nil,
        playRequest: RequestConfig? = nil
    ) throws -> SourceDefinition {
        let baseURL: URL = try #require(URL(string: "https://www.xvideos.com/"))
        return SourceDefinition(
            id: "generic.example",
            runtimeKind: .video,
            name: "Generic Example",
            baseURL: baseURL,
            version: nil,
            ownership: .user,
            comic: nil,
            rss: nil,
            video: VideoSourceDefinition(
                adapter: .genericHTML,
                entryURL: baseURL,
                seedURL: nil,
                entryKind: .home,
                routePatterns: nil,
                playbackPolicy: .playPageFirst,
                sharedRequest: sharedRequest,
                listRequest: listRequest,
                detailRequest: detailRequest,
                playRequest: playRequest,
                requiresAccount: false,
                seedVodID: nil,
                seedSourceIndex: nil,
                seedEpisodeIndex: nil,
                seedDetailURL: nil,
                seedPlayURL: nil
            ),
            plugin: nil
        )
    }

    private static func arteVideoDefinition(
        sharedRequest: RequestConfig? = nil,
        listRequest: RequestConfig? = nil,
        detailRequest: RequestConfig? = nil,
        playRequest: RequestConfig? = nil
    ) throws -> SourceDefinition {
        let baseURL: URL = try #require(URL(string: "https://www.arte.tv/"))
        let entryURL: URL = try #require(URL(string: "https://www.arte.tv/en/videos/"))
        return SourceDefinition(
            id: "arte.webview.generic",
            runtimeKind: .video,
            name: "ARTE Videos",
            baseURL: baseURL,
            version: nil,
            ownership: .user,
            comic: nil,
            rss: nil,
            video: VideoSourceDefinition(
                adapter: .genericHTML,
                entryURL: entryURL,
                seedURL: nil,
                entryKind: .list,
                routePatterns: nil,
                playbackPolicy: .playPageFirst,
                sharedRequest: sharedRequest,
                listRequest: listRequest,
                detailRequest: detailRequest,
                playRequest: playRequest,
                requiresAccount: false,
                seedVodID: nil,
                seedSourceIndex: nil,
                seedEpisodeIndex: nil,
                seedDetailURL: nil,
                seedPlayURL: nil
            ),
            plugin: nil
        )
    }
}

private final class RecordingVideoPageContentLoader: PageContentLoader {
    let html: String
    private(set) var lastRequest: RequestConfig?

    init(html: String) {
        self.html = html
    }

    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        self.lastRequest = request
        return self.html
    }
}
