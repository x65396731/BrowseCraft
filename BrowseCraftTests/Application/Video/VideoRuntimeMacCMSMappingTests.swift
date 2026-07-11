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

    @Test func urlResolverRejectsRSSAndKeepsGenericRoutesInspectable() throws {
        let resolver: VideoSourceURLResolver = VideoSourceURLResolver()

        do {
            _ = try resolver.resolve("https://video.example.test/rss.xml")
            Issue.record("Expected RSS route to be rejected.")
        } catch VideoSourceURLResolverError.rssURLNotVideo {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }

        let genericRoute: VideoSourceURLResolution = try resolver.resolve("https://video.example.test/topic/weekly.html")
        #expect(genericRoute.entryURL.absoluteString == "https://video.example.test/topic/weekly.html")
        #expect(genericRoute.defaultListURL?.absoluteString == "https://video.example.test/topic/weekly.html")
        #expect(genericRoute.seedURL == nil)
    }

    @Test func macCMSMapperExtractsListDetailAndPlaybackReferences() throws {
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper()
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
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper()
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

    @Test func macCMSMapperExtractsVfedListItemsAndSlashRoutes() throws {
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let listURL: URL = try #require(URL(string: "https://www.kpkuang.fun/vodtype/1/"))

        let items: [SourceContentItem] = try mapper.mapList(
            html: Self.vfedListHTML,
            definition: definition,
            pageURL: listURL
        )

        #expect(items.count == 1)
        #expect(items[0].id == "video.example.video.666009")
        #expect(items[0].title == "波波仔大电影2")
        #expect(items[0].detailURL?.absoluteString == "https://www.kpkuang.fun/voddetail/666009/")
        #expect(items[0].coverURL?.absoluteString == "https://www.kpkuang.fun/upload/vfed-cover.jpg")
        #expect(items[0].latestText == "HD")
    }

    @Test func macCMSMapperFiltersVfedRecommendationCards() throws {
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let listURL: URL = try #require(URL(string: "https://www.kpkuang.fun/vodtype/1/"))

        let items: [SourceContentItem] = try mapper.mapList(
            html: Self.vfedRecommendationHTML,
            definition: definition,
            pageURL: listURL
        )

        #expect(items.isEmpty)
    }

    @Test func macCMSMapperExtractsVfedEpisodeSlashRoutes() throws {
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let detailURL: URL = try #require(URL(string: "https://www.kpkuang.fun/voddetail/666009/"))

        let detail: VideoDetailContent = try mapper.mapDetail(
            html: Self.vfedDetailHTML,
            definition: definition,
            detailURL: detailURL
        )

        #expect(detail.episodes.map(\.id) == ["666009-1-1"])
        #expect(detail.episodes.map(\.title) == ["正片"])
        #expect(detail.episodes[0].playPageURL.absoluteString == "https://www.kpkuang.fun/vodplay/666009-1-1/")
    }

    @Test func macCMSMapperUsesMostCompleteVfedPlaybackList() throws {
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let detailURL: URL = try #require(URL(string: "https://www.kpkuang.fun/voddetail/1091565/"))

        let detail: VideoDetailContent = try mapper.mapDetail(
            html: Self.vfedMultiLineDetailHTML,
            definition: definition,
            detailURL: detailURL
        )

        #expect(detail.episodes.map(\.id) == ["1091565-23-1", "1091565-23-2", "1091565-23-3"])
        #expect(detail.episodes.map(\.title) == ["第1集", "第2集", "第3集"])
    }

    @Test func macCMSMapperFallsBackWhenOnlyVfedVIPPlaybackListsExist() throws {
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let detailURL: URL = try #require(URL(string: "https://www.kpkuang.fun/voddetail/900001/"))

        let detail: VideoDetailContent = try mapper.mapDetail(
            html: Self.vfedOnlyVIPDetailHTML,
            definition: definition,
            detailURL: detailURL
        )

        #expect(detail.episodes.map(\.id) == ["900001-7-1", "900001-7-2"])
        #expect(detail.episodes.map(\.title) == ["第1集", "第2集"])
    }

    @Test func macCMSMapperSortsVfedEpisodeTitlesNumerically() throws {
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let detailURL: URL = try #require(URL(string: "https://www.kpkuang.fun/voddetail/900002/"))

        let detail: VideoDetailContent = try mapper.mapDetail(
            html: Self.vfedUnsortedEpisodeDetailHTML,
            definition: definition,
            detailURL: detailURL
        )

        #expect(detail.episodes.map(\.title) == ["S1_EP10_中文字幕", "S1_EP29_中文字幕", "S1_EP30_中文字幕"])
    }

    @Test func macCMSMapperClassifiesMP4AndEmptyPlayerPayload() throws {
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper()
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
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper()
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
        #expect(playback.candidateMediaKind == .iframePlayer)
        #expect(playback.status == .pageOnly)
    }

    @Test func macCMSMapperFiltersKnownAdMediaPayload() throws {
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let playURL: URL = try #require(URL(string: "https://video.example.test/vodplay/117372-1-1.html"))

        let playback: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: """
            <script>
              var player_aaaa={"url":"https://vv.jisuzyv.com/play/dBBNZZJd/index.m3u8","from":"adline","id":"117372","sid":15,"nid":1};
            </script>
            """,
            definition: definition,
            playPageURL: playURL
        )

        #expect(playback.candidateMediaKind == .m3u8)
        #expect(playback.status == .failed(.mediaURLNotFound))
    }

    @Test func iframePlayerResolverFallsBackToWebPlaybackWhenStaticMediaIsMissing() async throws {
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let playURL: URL = try #require(URL(string: "https://video.example.test/vodplay/117372-1-1.html"))
        let initialReference: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: """
            <script>
              var player_aaaa={"url":"https://player.example.test/player/117372-1-1","from":"iframe","id":"117372","sid":1,"nid":1};
            </script>
            """,
            definition: definition,
            playPageURL: playURL
        )

        let resolver: VideoIframePlayerResolver = VideoIframePlayerResolver(
            pageContentLoader: StaticMacCMSPlaybackPageContentLoader(
                html: "<html><body>iframe player shell without direct media</body></html>"
            ),
            mapper: mapper
        )
        let optionalResolution: VideoIframePlayerResolution? = try await resolver.resolve(
            reference: initialReference,
            definition: definition,
            baseRequest: nil
        )
        let resolution: VideoIframePlayerResolution = try #require(optionalResolution)

        #expect(resolution.reference.status == .pageOnly)
        #expect(resolution.reference.candidateMediaURL?.absoluteString == "https://player.example.test/player/117372-1-1")
        #expect(resolution.reference.candidateMediaKind == .iframePlayer)
        #expect(resolution.issues.contains { issue in
            issue.id == "video.iframePlayerMediaMissing"
        })
    }

    @Test func iframePlayerResolverTreatsDirectMediaCandidateAsPlayable() async throws {
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let playURL: URL = try #require(URL(string: "https://video.example.test/vodplay/117372-1-1.html"))
        let reference: SourceVideoPlaybackReference = SourceVideoPlaybackReference(
            vodID: "117372",
            sourceIndex: 1,
            episodeIndex: 1,
            episodeKey: "117372-1-1",
            episodeTitle: "第1集",
            playPageURL: playURL,
            candidateMediaURL: try #require(URL(string: "https://media.example.test/video/index.m3u8")),
            candidateMediaKind: .iframePlayer,
            playbackRequestConfig: nil,
            nextEpisodeURL: nil,
            previousEpisodeURL: nil,
            sourceName: "iframe",
            status: .pageOnly
        )

        let resolver: VideoIframePlayerResolver = VideoIframePlayerResolver(
            pageContentLoader: StaticMacCMSPlaybackPageContentLoader(html: ""),
            mapper: mapper
        )
        let optionalResolution: VideoIframePlayerResolution? = try await resolver.resolve(
            reference: reference,
            definition: definition,
            baseRequest: nil
        )
        let resolution: VideoIframePlayerResolution = try #require(optionalResolution)

        #expect(resolution.reference.status == .playable)
        #expect(resolution.reference.candidateMediaURL?.absoluteString == "https://media.example.test/video/index.m3u8")
        #expect(resolution.reference.candidateMediaKind == .m3u8)
        #expect(resolution.reference.playbackRequestConfig?.referer == playURL)
    }

    @Test func iframePlayerResolverTreatsNestedDirectMediaAsPlayable() async throws {
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper()
        let definition: SourceDefinition = try Self.videoDefinition()
        let playURL: URL = try #require(URL(string: "https://video.example.test/vodplay/117372-1-1.html"))
        let initialReference: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: """
            <script>
              var player_aaaa={"url":"https://player.example.test/player/117372-1-1","from":"iframe","id":"117372","sid":1,"nid":1};
            </script>
            """,
            definition: definition,
            playPageURL: playURL
        )

        let resolver: VideoIframePlayerResolver = VideoIframePlayerResolver(
            pageContentLoader: StaticMacCMSPlaybackPageContentLoader(
                html: """
                <script>
                  var player_aaaa={"url":"https://media.example.test/video/index.m3u8","from":"m3u8","id":"117372","sid":1,"nid":1};
                </script>
                """
            ),
            mapper: mapper
        )
        let optionalResolution: VideoIframePlayerResolution? = try await resolver.resolve(
            reference: initialReference,
            definition: definition,
            baseRequest: nil
        )
        let resolution: VideoIframePlayerResolution = try #require(optionalResolution)

        #expect(resolution.reference.status == .playable)
        #expect(resolution.reference.candidateMediaURL?.absoluteString == "https://media.example.test/video/index.m3u8")
        #expect(resolution.reference.candidateMediaKind == .m3u8)
        #expect(resolution.reference.playbackRequestConfig?.referer?.absoluteString == "https://player.example.test/player/117372-1-1")
    }

    @Test func macCMSMapperExtractsVfedIframePlayerBeforeRestrictionText() throws {
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper(
            lexicon: VideoDetectionLexicon(
                sourceLexicon: SourceDetectionLexicon.load(language: .simplifiedChinese)
            )
        )
        let definition: SourceDefinition = try Self.videoDefinition()
        let playURL: URL = try #require(URL(string: "https://www.kpkuang.fun/vodplay/1058034-3-1.html"))

        let playback: SourceVideoPlaybackReference = try mapper.mapPlayback(
            html: Self.vfedPlaybackHTML,
            definition: definition,
            playPageURL: playURL
        )

        #expect(playback.vodID == "1058034")
        #expect(playback.sourceIndex == 3)
        #expect(playback.episodeIndex == 1)
        #expect(playback.candidateMediaURL?.absoluteString == "https://abyssplayer.com/_4oi_-qJR")
        #expect(playback.candidateMediaKind == .iframePlayer)
        #expect(playback.status == .pageOnly)
    }

    @Test func macCMSMapperClassifiesRestrictedAndPageOnlyPlayback() throws {
        let mapper: MacCMSVideoContentMapper = MacCMSVideoContentMapper(
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

    @Test func videoAdapterDetectorKeepsMacCMSSignalsAsFacts() throws {
        let detector: VideoAdapterDetector = VideoAdapterDetector()
        let routeURL: URL = try #require(URL(string: "https://video.example.test/voddetail/117372.html"))
        let routeDetection: VideoAdapterDetection = detector.detect(
            VideoAdapterDetectionInput(url: routeURL)
        )
        #expect(routeDetection.adapter == .genericHTML)
        #expect(routeDetection.confidence >= 0.75)
        #expect(routeDetection.reasons.contains { reason in
            reason.contains("Content mapper adapter was not inferred")
        })

        let homeURL: URL = try #require(URL(string: "https://video.example.test/"))
        let htmlDetection: VideoAdapterDetection = detector.detect(
            VideoAdapterDetectionInput(
                url: homeURL,
                html: "<script>var player_aaaa={\"url\":\"\"};</script><div>mac_history vod_name</div>"
            )
        )
        #expect(htmlDetection.adapter == .genericHTML)
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

    private static let vfedListHTML: String = """
    <html>
      <body>
        <ul>
          <li id="listid_666009_7295" class="fed-list-item fed-padding fed-col-xs4 fed-col-sm3 fed-col-md2">
            <a class="fed-list-pics fed-lazy fed-part-2by3" href="/voddetail/666009/" title="波波仔大电影2" data-original="/upload/vfed-cover.jpg">
              <span class="fed-list-remarks">HD</span>
            </a>
            <a class="fed-list-title" href="/voddetail/666009/" title="波波仔大电影2">
              <h4>备用标题</h4>
            </a>
          </li>
        </ul>
      </body>
    </html>
    """

    private static let vfedRecommendationHTML: String = """
    <html>
      <body>
        <ul>
          <li class="fed-list-item fed-padding fed-col-xs12 fed-col-sm6 fed-col-md4">
            <a class="fed-list-pics fed-lazy fed-part-2by1" href="/voddetail/1069266/" data-original="/upload/recommend.jpg">
              <span class="cinema_title">惩罚者：最后一击</span>
            </a>
          </li>
        </ul>
      </body>
    </html>
    """

    private static let vfedDetailHTML: String = """
    <html>
      <body>
        <a class="fed-deta-play" href="/vodplay/666009-1-1/">立即播放</a>
        <li class="fed-play-item fed-drop-item">
          <ul class="fed-drop-head fed-padding fed-part-rows">
            <li>来自 <span class="uk-label">腾讯视频-VIP解析</span> 的播放列表</li>
          </ul>
          <ul class="fed-part-rows">
            <li>
              <a href="/vodplay/666009-7-1/">VIP正片</a>
            </li>
          </ul>
        </li>
        <li class="fed-play-item fed-drop-item">
          <ul class="fed-drop-head fed-padding fed-part-rows">
            <li>来自 <span class="uk-label">IK影视</span> 的播放列表</li>
          </ul>
          <ul class="fed-part-rows">
            <li>
              <a href="/vodplay/666009-1-1/">正片</a>
            </li>
          </ul>
        </li>
        <li class="fed-play-item fed-drop-item">
          <ul class="fed-drop-head fed-padding fed-part-rows">
            <li>来自 <span class="uk-label">量子云</span> 的播放列表</li>
          </ul>
          <ul class="fed-part-rows">
            <li>
              <a href="/vodplay/666009-12-1/">正片</a>
            </li>
          </ul>
        </li>
      </body>
    </html>
    """

    private static let vfedMultiLineDetailHTML: String = """
    <html>
      <body>
        <li class="fed-play-item fed-drop-item">
          <ul class="fed-drop-head fed-padding fed-part-rows">
            <li>来自 <span class="uk-label">腾讯视频-VIP解析</span> 的播放列表</li>
          </ul>
          <ul class="fed-part-rows">
            <li><a href="/vodplay/1091565-7-1/">第1集</a></li>
            <li><a href="/vodplay/1091565-7-2/">第2集</a></li>
            <li><a href="/vodplay/1091565-7-3/">第3集</a></li>
          </ul>
        </li>
        <li class="fed-play-item fed-drop-item">
          <ul class="fed-drop-head fed-padding fed-part-rows">
            <li>来自 <span class="uk-label">电影天堂</span> 的播放列表</li>
          </ul>
          <ul class="fed-part-rows">
            <li><a href="/vodplay/1091565-21-1/">第1集</a></li>
            <li><a href="/vodplay/1091565-21-2/">第2集</a></li>
          </ul>
        </li>
        <li class="fed-play-item fed-drop-item">
          <ul class="fed-drop-head fed-padding fed-part-rows">
            <li>来自 <span class="uk-label">量子云</span> 的播放列表</li>
          </ul>
          <ul class="fed-part-rows">
            <li><a href="/vodplay/1091565-23-1/">第1集</a></li>
            <li><a href="/vodplay/1091565-23-2/">第2集</a></li>
            <li><a href="/vodplay/1091565-23-3/">第3集</a></li>
          </ul>
        </li>
      </body>
    </html>
    """

    private static let vfedOnlyVIPDetailHTML: String = """
    <html>
      <body>
        <li class="fed-play-item fed-drop-item">
          <ul class="fed-drop-head fed-padding fed-part-rows">
            <li>来自 <span class="uk-label">腾讯视频-VIP解析</span> 的播放列表</li>
          </ul>
          <ul class="fed-part-rows">
            <li><a href="/vodplay/900001-7-1/">第1集</a></li>
            <li><a href="/vodplay/900001-7-2/">第2集</a></li>
          </ul>
        </li>
      </body>
    </html>
    """

    private static let vfedUnsortedEpisodeDetailHTML: String = """
    <html>
      <body>
        <li class="fed-play-item fed-drop-item">
          <ul class="fed-drop-head fed-padding fed-part-rows">
            <li>来自 <span class="uk-label">字幕云</span> 的播放列表</li>
          </ul>
          <ul class="fed-part-rows">
            <li><a href="/vodplay/900002-1-29/">S1_EP29_中文字幕</a></li>
            <li><a href="/vodplay/900002-1-30/">S1_EP30_中文字幕</a></li>
            <li><a href="/vodplay/900002-1-10/">S1_EP10_中文字幕</a></li>
          </ul>
        </li>
      </body>
    </html>
    """

    private static let vfedPlaybackHTML: String = """
    <html>
      <body>
        <a class="fed-navs-login" href="javascript:;">登录</a>
        <div class="fed-play-player">
          <iframe id="fed-play-iframe" class="fed-play-iframe" data-play="NDoaHR0cHM6Ly9hYnlzc3BsYXllci5jb20vXzRvaV8tcUpS"></iframe>
          <div class="fed-play-confirm">
            <p>提示：购买VIP会员组，享受超级权限，谢谢支持。</p>
            <a class="fed-navs-login" href="javascript:;">立即登录</a>
          </div>
        </div>
        <div class="fed-play-title">
          <span class="fed-play-text">木乃伊TC_原声_中文字幕</span>
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

private final class StaticMacCMSPlaybackPageContentLoader: PageContentLoader {
    let html: String

    init(html: String) {
        self.html = html
    }

    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        return self.html
    }
}
