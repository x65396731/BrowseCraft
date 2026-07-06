import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：P5.1.7 使用真实 genericHTML 样本固定静态 HTML 和播放器脚本解析，不验证媒体 URL 长期可播放。
struct VideoRuntimeGenericHTMLMappingTests {
    @Test func genericHTMLMapperExtractsXVideosLikeListItems() throws {
        let mapper: any VideoHTMLMapper = VideoAdapterRegistry().mapper(for: .genericHTML)
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

    @Test func genericHTMLMapperBuildsDetailContentFromPlayablePage() throws {
        let mapper: any VideoHTMLMapper = VideoAdapterRegistry().mapper(for: .genericHTML)
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

    @Test func genericHTMLMapperExtractsHTML5PlayerPlaybackURL() throws {
        let mapper: any VideoHTMLMapper = VideoAdapterRegistry().mapper(for: .genericHTML)
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
        let mapper: GenericHTMLVideoHTMLMapper = GenericHTMLVideoHTMLMapper()
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
        let mapper: GenericHTMLVideoHTMLMapper = GenericHTMLVideoHTMLMapper()
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

        #expect(playback.candidateMediaKind == .iframe)
        #expect(playback.status == .pageOnly)
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

    private static func videoDefinition() throws -> SourceDefinition {
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
