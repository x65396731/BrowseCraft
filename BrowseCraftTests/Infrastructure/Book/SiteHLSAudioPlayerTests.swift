import BrowseCraftCore
import Foundation
import ReadiumNavigator
import ReadiumShared
import Testing
@testable import BrowseCraft

// 中文注释：书类 HLS 有声播放内核（fwq 设计稿第 83 节）：分流判据、播放地址与请求头、Locator 与 Readium 同形、失败状态码。
// 形状取自 otomekoe：章节 = 作品页（播放页型），音频是 `https://v.weeab0o.xyz/RJ01633471.m3u8`，不带同站 Referer 时 403。

@MainActor
struct SiteHLSAudioPlayerTests {
    private nonisolated static let hls: String = BookMediaFormat.hls.rwpmMediaType
    private nonisolated static let workPage: URL = URL(string: "https://otomekoe.moe/10804/")!
    private nonisolated static let playlist: URL = URL(string: "https://v.weeab0o.xyz/RJ01633471.m3u8")!

    private static func manifest(_ kinds: [BookPublicationItem.Kind], fromPage: Bool = false) -> BookPublicationManifest {
        let items: [BookPublicationItem] = kinds.enumerated().map { index, kind in
            let url: URL = URL(string: "https://audio.example.test/\(index)/")!
            return BookPublicationItem(href: url.absoluteString, title: "第\(index + 1)集", chapterURL: url, kind: kind, audioResolvedFromPage: fromPage)
        }
        return BookPublicationManifest(identifier: "s::d", title: "t", author: nil, language: nil, coverURL: nil, items: items)
    }

    /// 只有音频章节全是 HLS 才走 HLS 内核；mp3、混合、未知格式、文字书都照旧走 Readium。
    @Test func onlyAllHLSAudiobooksTakeTheHLSEngine() {
        #expect(Self.manifest([.audio(mediaType: Self.hls, durationSeconds: nil)]).isHLSAudiobook)
        #expect(Self.manifest([.audio(mediaType: Self.hls, durationSeconds: nil), .audio(mediaType: Self.hls, durationSeconds: nil)]).isHLSAudiobook)
        #expect(Self.manifest([.audio(mediaType: BookMediaFormat.mp3.rwpmMediaType, durationSeconds: nil)]).isHLSAudiobook == false)
        #expect(Self.manifest([.audio(mediaType: Self.hls, durationSeconds: nil), .audio(mediaType: nil, durationSeconds: nil)]).isHLSAudiobook == false)
        #expect(Self.manifest([.audio(mediaType: nil, durationSeconds: nil)]).isHLSAudiobook == false)
        #expect(Self.manifest([.text]).isHLSAudiobook == false)
    }

    /// 播放页型章节取页解析：规则没给 Referer 时以章节页为 Referer（与 `SiteBookAudioHTTPClient` 同口径），规则给的头保留。
    @Test func pageChapterResolvesToPlaylistWithChapterReferer() async throws {
        let item: BookPublicationItem = BookPublicationItem(
            href: Self.workPage.absoluteString,
            title: "作品",
            chapterURL: Self.workPage,
            kind: .audio(mediaType: Self.hls, durationSeconds: nil),
            audioResolvedFromPage: true
        )
        let manifest: BookPublicationManifest = BookPublicationManifest(
            identifier: "s::d", title: "t", author: nil, language: nil, coverURL: nil, items: [item]
        )
        let resolver: SiteHLSAudioPlayer.AudioResolver = SiteHLSAudioPlayer.audioResolver(manifest: manifest) { _ in
            return .audio([SourceBookAudioItem(url: Self.playlist, headers: ["User-Agent": "UA"])])
        }
        let resolved: SiteBookResolvedAudio = try await resolver(item)
        #expect(resolved.url == Self.playlist)
        #expect(resolved.headers["Referer"] == Self.workPage.absoluteString)
        #expect(resolved.headers["User-Agent"] == "UA")
    }

    /// 章节地址本身就是 m3u8 时原样播放，不取页。
    @Test func directPlaylistChapterIsPlayedAsIs() async throws {
        let item: BookPublicationItem = BookPublicationItem(
            href: Self.playlist.absoluteString,
            title: "第1集",
            chapterURL: Self.playlist,
            kind: .audio(mediaType: Self.hls, durationSeconds: nil)
        )
        let manifest: BookPublicationManifest = BookPublicationManifest(
            identifier: "s::d", title: "t", author: nil, language: nil, coverURL: nil, items: [item]
        )
        let resolver: SiteHLSAudioPlayer.AudioResolver = SiteHLSAudioPlayer.audioResolver(manifest: manifest) { _ in
            Issue.record("直链章节不应取页")
            return .audio([])
        }
        let resolved: SiteBookResolvedAudio = try await resolver(item)
        #expect(resolved.url == Self.playlist)
        #expect(resolved.headers.isEmpty)
    }

    /// http 先升 https；https 与其它地址不动。
    @Test func httpPlaylistIsUpgraded() {
        #expect(SiteHLSAudioPlayer.upgradedToHTTPS(URL(string: "http://v.example.test/a.m3u8?x=1")!).absoluteString == "https://v.example.test/a.m3u8?x=1")
        #expect(SiteHLSAudioPlayer.upgradedToHTTPS(Self.playlist) == Self.playlist)
    }

    /// 请求头放进 `AVURLAssetHTTPHeaderFieldsKey`（对播放列表与切片都生效；KSPlayer 同一个键）。
    @Test func headerKeyMatchesTheOneKSPlayerUses() {
        #expect(SiteHLSAudioPlayer.httpHeaderFieldsKey == "AVURLAssetHTTPHeaderFieldsKey")
        #expect(SiteHLSAudioPlayer.asset(for: SiteBookResolvedAudio(url: URL(string: "http://v.example.test/a.m3u8")!, headers: [:])).url.scheme == "https")
    }

    /// Locator 与 Readium `AudioNavigator` 同形：`t=` 片段可被 `locations.time` 读回，progression = 时间 / 时长；时长未知时没有 progression。
    @Test func locatorRoundTripsTimeLikeReadium() throws {
        let link: Link = Link(href: Self.workPage.absoluteString, mediaType: MediaType(Self.hls), title: "作品")
        let locator: Locator = SiteHLSAudioPlayer.locator(for: link, time: 125.5, duration: 251)
        #expect(locator.locations.time?.begin == 125.5)
        #expect(locator.locations.progression == 0.5)
        #expect(locator.href.string == Self.workPage.absoluteString)
        let json: String = try #require(BookReaderViewModel.json(from: locator))
        #expect(BookReaderViewModel.locator(fromJSON: json)?.locations.time?.begin == 125.5)
        #expect(SiteHLSAudioPlayer.locator(for: link, time: 10, duration: nil).locations.progression == nil)
    }

    /// AVFoundation 的 HTTP 失败写在错误日志说明里；读出状态码后按 `APP-MEMO-043` 归类（403 已失效）。
    @Test func httpStatusIsReadFromErrorLogComment() {
        #expect(SiteHLSAudioPlayer.httpStatusCode(inComment: "HTTP 403: Forbidden") == 403)
        #expect(SiteHLSAudioPlayer.httpStatusCode(inComment: "HTTP/1.1 404 Not Found") == nil)
        #expect(SiteHLSAudioPlayer.httpStatusCode(inComment: "HTTP 503: Service Unavailable") == 503)
        #expect(SiteHLSAudioPlayer.httpStatusCode(inComment: "The operation couldn’t be completed") == nil)
        // 中文注释：模拟器实网里播放项错误的底层错误描述（中文界面）原样。
        let underlying: NSError = NSError(domain: "CoreMediaErrorDomain", code: -12660, userInfo: [
            "NSDescription": "未能完成操作。（CoreMediaErrorDomain错误-12660 - HTTP 403: Forbidden）"
        ])
        let error: NSError = NSError(domain: NSURLErrorDomain, code: -1102, userInfo: [NSUnderlyingErrorKey: underlying])
        #expect(SiteHLSAudioPlayer.httpStatusCode(inComment: String(describing: error)) == 403)
    }

    /// 播放状态映射与 Readium 一致：等待缓冲算加载中。
    @Test func timeControlStatusMapsLikeReadium() {
        #expect(SiteHLSAudioPlayer.state(of: .paused) == .paused)
        #expect(SiteHLSAudioPlayer.state(of: .waitingToPlayAtSpecifiedRate) == .loading)
        #expect(SiteHLSAudioPlayer.state(of: .playing) == .playing)
    }
}
