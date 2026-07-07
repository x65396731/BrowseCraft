import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：P4.13.6 固定 MacCMS 视频站点规则验证的本地样本，不访问真实站点或绕过受限内容。
struct VideoRuntimeMacCMSMappingTests {
    @Test func urlResolverNormalizesSupportedMacCMSRoutes() throws {
        let resolver: VideoSourceURLResolver = VideoSourceURLResolver()

        let home: VideoSourceURLResolution = try resolver.resolve("http://video.example.test/")
        #expect(home.baseURL.absoluteString == "https://video.example.test/")
        #expect(home.entryKind == .home)
        #expect(home.defaultListURL?.absoluteString == "https://video.example.test/")

        let category: VideoSourceURLResolution = try resolver.resolve("https://video.example.test/vodtype/2.html")
        #expect(category.entryKind == .category)
        #expect(category.normalizedEntryURL.absoluteString == "https://video.example.test/vodtype/2.html")

        let list: VideoSourceURLResolution = try resolver.resolve("https://video.example.test/vodshow/movie--------2---2026.html")
        #expect(list.entryKind == .list)
        #expect(list.defaultListURL?.absoluteString == "https://video.example.test/vodshow/movie--------2---2026.html")

        let detail: VideoSourceURLResolution = try resolver.resolve("https://video.example.test/voddetail/117372.html")
        #expect(detail.entryKind == .detail)
        #expect(detail.vodID == "117372")
        #expect(detail.seedDetailURL?.absoluteString == "https://video.example.test/voddetail/117372.html")

        let play: VideoSourceURLResolution = try resolver.resolve("https://video.example.test/vodplay/117372-1-2.html")
        #expect(play.entryKind == .play)
        #expect(play.vodID == "117372")
        #expect(play.sourceIndex == 1)
        #expect(play.episodeIndex == 2)
        #expect(play.seedDetailURL?.absoluteString == "https://video.example.test/voddetail/117372.html")
    }

    @Test func urlResolverRejectsRSSAndUnsupportedRoutes() throws {
        let resolver: VideoSourceURLResolver = VideoSourceURLResolver()

        do {
            _ = try resolver.resolve("https://video.example.test/rss.xml")
            Issue.record("Expected RSS route to be rejected.")
        } catch VideoSourceURLResolverError.rssURLNotVideo {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }

        do {
            _ = try resolver.resolve("https://video.example.test/topic/weekly.html")
            Issue.record("Expected unsupported route to be rejected.")
        } catch VideoSourceURLResolverError.unsupportedVideoURL {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func macCMSMapperExtractsListDetailAndPlaybackReferences() throws {
        let mapper: MacCMSVideoHTMLMapper = MacCMSVideoHTMLMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let listURL: URL = try #require(URL(string: "https://video.example.test/vodtype/2.html"))
        let detailURL: URL = try #require(URL(string: "https://video.example.test/voddetail/117372.html"))
        let playURL: URL = try #require(URL(string: "https://video.example.test/vodplay/117372-1-1.html"))

        let items: [SourceContentItem] = try mapper.mapList(
            html: Self.listHTML,
            definition: definition,
            pageURL: listURL
        )
        #expect(items.count == 1)
        #expect(items[0].id == "video.example.video.117372")
        #expect(items[0].title == "示例影片")
        #expect(items[0].detailURL?.absoluteString == "https://video.example.test/voddetail/117372.html")
        #expect(items[0].coverURL?.absoluteString == "https://video.example.test/upload/cover.jpg")
        #expect(items[0].latestText == "第02集")

        let detail: VideoDetailContent = try mapper.mapDetail(
            html: Self.detailHTML,
            definition: definition,
            detailURL: detailURL
        )
        #expect(detail.episodes.map(\.id) == ["117372-1-1", "117372-1-2"])
        #expect(detail.episodes.map(\.title) == ["第1集", "第2集"])
        #expect(detail.episodes[1].playPageURL.absoluteString == "https://video.example.test/vodplay/117372-1-2.html")
        #expect(detail.synopsis == "这是一段超过三十个字的测试剧情，用来确认详情页简介不会被主演或导演行误判。")
        #expect(detail.metadataRows.contains("主演：测试演员"))

        let playback: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: Self.playbackHTML,
            definition: definition,
            playPageURL: playURL
        )
        #expect(playback.vodID == "117372")
        #expect(playback.sourceIndex == 1)
        #expect(playback.episodeIndex == 1)
        #expect(playback.episodeKey == "117372-1-1")
        #expect(playback.episodeTitle == "第1集")
        #expect(playback.candidateMediaURL?.absoluteString == "https://media.example.test/video/index.m3u8")
        #expect(playback.candidateMediaKind == .m3u8)
        #expect(playback.playbackRequestConfig?.headers["Referer"] == "https://video.example.test/vodplay/117372-1-1.html")
        #expect(playback.nextEpisodeURL?.absoluteString == "https://video.example.test/vodplay/117372-1-2.html")
        #expect(playback.previousEpisodeURL?.absoluteString == "https://video.example.test/vodplay/117372-1-0.html")
        #expect(playback.sourceName == "testline")
        #expect(playback.status == .playable)
    }

    @Test func macCMSMapperUsesSkinSelectorFallbacks() throws {
        let mapper: MacCMSVideoHTMLMapper = MacCMSVideoHTMLMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let listURL: URL = try #require(URL(string: "https://video.example.test/vodtype/2.html"))
        let detailURL: URL = try #require(URL(string: "https://video.example.test/voddetail/117372.html"))

        let items: [SourceContentItem] = try mapper.mapList(
            html: Self.stuiListHTML,
            definition: definition,
            pageURL: listURL
        )
        #expect(items.count == 1)
        #expect(items[0].title == "Stui 示例影片")
        #expect(items[0].coverURL?.absoluteString == "https://video.example.test/stui-cover.jpg")
        #expect(items[0].latestText == "更新至03集")

        let detail: VideoDetailContent = try mapper.mapDetail(
            html: Self.moduleDetailHTML,
            definition: definition,
            detailURL: detailURL
        )
        #expect(detail.episodes.map(\.id) == ["117372-1-3"])
        #expect(detail.episodes.map(\.title) == ["第3集"])
    }

    @Test func macCMSMapperClassifiesMP4AndEmptyPlayerPayload() throws {
        let mapper: MacCMSVideoHTMLMapper = MacCMSVideoHTMLMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let playURL: URL = try #require(URL(string: "https://video.example.test/vodplay/117372-1-1.html"))

        let mp4: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: """
            <script>
              var player_aaaa={"url":"https://media.example.test/video/movie.mp4","from":"mp4","id":"117372","sid":1,"nid":1};
            </script>
            """,
            definition: definition,
            playPageURL: playURL
        )
        #expect(mp4.candidateMediaKind == .mp4)
        #expect(mp4.status == .playable)

        let empty: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: "<script>var player_aaaa={\"url\":\"\",\"id\":\"117372\",\"sid\":1,\"nid\":1};</script>",
            definition: definition,
            playPageURL: playURL
        )
        #expect(empty.status == .failed(.mediaURLNotFound))
    }

    @Test func macCMSMapperClassifiesIframePlayerPayloadAsPageOnly() throws {
        let mapper: MacCMSVideoHTMLMapper = MacCMSVideoHTMLMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let playURL: URL = try #require(URL(string: "https://video.example.test/vodplay/117372-1-1.html"))

        let playback: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: """
            <script>
              var player_aaaa={"url":"/embed/117372-1-1","from":"iframe","id":"117372","sid":1,"nid":1};
            </script>
            """,
            definition: definition,
            playPageURL: playURL
        )

        #expect(playback.candidateMediaURL?.absoluteString == "https://video.example.test/embed/117372-1-1")
        #expect(playback.candidateMediaKind == .iframe)
        #expect(playback.status == .pageOnly)
    }

    @Test func macCMSMapperClassifiesRestrictedAndPageOnlyPlayback() throws {
        let mapper: MacCMSVideoHTMLMapper = MacCMSVideoHTMLMapper(
            lexicon: VideoDetectionLexicon(
                sourceLexicon: SourceDetectionLexicon.load(language: .simplifiedChinese)
            )
        )
        let definition: SourceDefinition = try Self.videoDefinition()
        let playURL: URL = try #require(URL(string: "https://video.example.test/vodplay/117372-1-1.html"))

        let login: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: "请登录后继续观看<script>var player_aaaa={\"url\":\"\"};</script>",
            definition: definition,
            playPageURL: playURL
        )
        #expect(login.status == .restricted(.requiresLogin))
        #expect(login.candidateMediaKind == .unknown)

        let vip: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: "VIP 专享内容<script>var player_aaaa={\"url\":\"\"};</script>",
            definition: definition,
            playPageURL: playURL
        )
        #expect(vip.status == .restricted(.vipOnly))

        let pageOnly: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: "<html><body>普通播放页，没有直链</body></html>",
            definition: definition,
            playPageURL: playURL
        )
        #expect(pageOnly.status == .pageOnly)
    }

    @Test func videoAdapterDetectorIdentifiesMacCMSFromRouteAndHTMLSignals() throws {
        let detector: VideoAdapterDetector = VideoAdapterDetector()
        let routeURL: URL = try #require(URL(string: "https://video.example.test/voddetail/117372.html"))
        let routeDetection: VideoAdapterDetection = detector.detect(
            VideoAdapterDetectionInput(url: routeURL)
        )
        #expect(routeDetection.adapter == .macCMS)
        #expect(routeDetection.confidence >= 0.80)

        let homeURL: URL = try #require(URL(string: "https://video.example.test/"))
        let htmlDetection: VideoAdapterDetection = detector.detect(
            VideoAdapterDetectionInput(
                url: homeURL,
                html: "<script>var player_aaaa={\"url\":\"\"};</script><div>mac_history vod_name</div>"
            )
        )
        #expect(htmlDetection.adapter == .macCMS)
        #expect(htmlDetection.reasons.isEmpty == false)
    }

    private static func videoDefinition() throws -> SourceDefinition {
        let baseURL: URL = try #require(URL(string: "https://video.example.test/"))
        return SourceDefinition(
            id: "video.example",
            runtimeKind: .video,
            name: "Video Example",
            baseURL: baseURL,
            version: nil,
            ownership: .user,
            comic: nil,
            rss: nil,
            video: VideoSourceDefinition(
                adapter: .macCMS,
                entryURL: baseURL,
                seedURL: nil,
                entryKind: .home,
                routePatterns: .macCMS,
                playbackPolicy: .playPageFirst,
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

    private static let listHTML: String = """
    <html>
      <body>
        <div class="ewave-vodlist__box">
          <a class="thumb-link ewave-vodlist__thumb" href="/voddetail/117372.html" title="示例影片" data-original="/upload/cover.jpg"></a>
          <div class="ewave-vodlist__detail">
            <h4><a href="/voddetail/117372.html">备用标题</a></h4>
          </div>
          <span class="pic-text text-right">第02集</span>
        </div>
      </body>
    </html>
    """

    private static let detailHTML: String = """
    <html>
      <body>
        <div class="ewave-content__detail">
          <p>主演：测试演员</p>
          <p>导演：测试导演</p>
          <p>剧情简介：这是一段超过三十个字的测试剧情，用来确认详情页简介不会被主演或导演行误判。</p>
        </div>
        <div class="ewave-content__playlist">
          <a href="/vodplay/117372-1-1.html">第1集</a>
          <a href="/vodplay/117372-1-2.html">第2集</a>
        </div>
      </body>
    </html>
    """

    private static let stuiListHTML: String = """
    <html>
      <body>
        <div class="stui-vodlist__box">
          <a class="stui-vodlist__thumb" href="/voddetail/117372.html" title="Stui 示例影片" data-original="/stui-cover.jpg"></a>
          <span class="pic-text">更新至03集</span>
        </div>
      </body>
    </html>
    """

    private static let moduleDetailHTML: String = """
    <html>
      <body>
        <div class="module-play-list">
          <a href="/vodplay/117372-1-3.html">第3集</a>
        </div>
      </body>
    </html>
    """

    private static let playbackHTML: String = """
    <html>
      <body>
        <div class="ewave-player__detail">
          <h1 class="title"><a>第1集</a></h1>
        </div>
        <script>
          var player_aaaa={"url":"https://media.example.test/video/index.m3u8","from":"testline","id":"117372","sid":1,"nid":1,"link_next":"/vodplay/117372-1-2.html","link_pre":"/vodplay/117372-1-0.html"};
        </script>
      </body>
    </html>
    """
}
