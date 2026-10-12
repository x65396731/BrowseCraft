import BrowseCraftCore
import BrowseCraftDomain
import Foundation
import ReadiumShared
import Testing
@testable import BrowseCraft

// 中文注释：音频请求 http → https 升级；https 与非 http 原样。
struct SiteBookAudioHTTPClientTests {
    @Test func httpRequestsAreUpgradedToHTTPS() throws {
        let http: HTTPURL = try #require(HTTPURL(url: URL(string: "http://www.archive.org/download/a/b_64kb.mp3?x=1")!))
        let upgraded: HTTPRequest = SiteBookAudioHTTPClient.upgradedToHTTPS(HTTPRequest(url: http))
        #expect(upgraded.url.url.absoluteString == "https://www.archive.org/download/a/b_64kb.mp3?x=1")

        let https: HTTPURL = try #require(HTTPURL(url: URL(string: "https://archive.org/download/a/b.mp3")!))
        #expect(SiteBookAudioHTTPClient.upgradedToHTTPS(HTTPRequest(url: https)).url.isEquivalentTo(https))
    }

    @Test func clientKeepsItsDelegateAlive() {
        let client: SiteBookAudioHTTPClient = SiteBookAudioHTTPClient()
        #expect(client.client.delegate === client)
    }
}

// 中文注释：fwq 设计稿第 46 节 A1 / A2：播放页型有声章节。规则是有声（`audio-media` 的 DOM 支）、章节地址是播放页时
// 仍装成音频章节；播放器请求播放页时先取页解析出音频地址再改写请求，补 Referer；一章只取一次页。
struct SiteBookPlayPageAudioTests {
    private static let playPage: URL = URL(string: "https://www.example.test/book/14929-1")!
    private static let audio: URL = URL(string: "https://audio.example.test/a/1.m4a")!

    @Test func playPageChaptersOfAnAudioRuleAreAssembledAsAudio() throws {
        let manifest: BookPublicationManifest = BookPublicationAssembler().assemble(
            source: try Self.source(reader: Self.audioReader),
            detailURL: URL(string: "https://www.example.test/book/14929")!,
            detail: Self.detail([Self.playPage, URL(string: "https://audio.example.test/a/2.mp3")!])
        )
        #expect(manifest.isAudiobook)
        #expect(manifest.items.map(\.audioResolvedFromPage) == [true, false])
        #expect(manifest.items[0].href == Self.playPage.absoluteString)
        guard case .audio = manifest.items[0].kind else {
            Issue.record("播放页章节应装成音频：\(manifest.items[0].kind)")
            return
        }
    }

    @Test func textRuleChaptersStayText() throws {
        let manifest: BookPublicationManifest = BookPublicationAssembler().assemble(
            source: try Self.source(reader: Self.textReader),
            detailURL: URL(string: "https://www.example.test/book/1")!,
            detail: Self.detail([URL(string: "https://www.example.test/book/1/1.html")!])
        )
        #expect(manifest.items.map(\.kind) == [.text])
        #expect(manifest.items.map(\.audioResolvedFromPage) == [false])
    }

    @Test func resolverLoadsEachPlayPageOnceAndAddsReferer() async throws {
        let calls: CallCounter = CallCounter()
        let resolver: SiteBookPageAudioResolver = SiteBookPageAudioResolver(chapters: [Self.playPage]) { url in
            await calls.increment()
            #expect(url == Self.playPage)
            return .audio([SourceBookAudioItem(url: Self.audio, mediaType: "audio/mp4")])
        }
        let first: SiteBookResolvedAudio? = try await resolver.resolve(Self.playPage)
        let second: SiteBookResolvedAudio? = try await resolver.resolve(Self.playPage)
        #expect(first == SiteBookResolvedAudio(url: Self.audio, headers: ["Referer": Self.playPage.absoluteString]))
        #expect(second == first)
        #expect(await calls.value == 1)
        #expect(try await resolver.resolve(Self.audio) == nil)
    }

    @Test func resolverKeepsRuleRefererAndRejectsTextContent() async throws {
        let withReferer: SiteBookPageAudioResolver = SiteBookPageAudioResolver(chapters: [Self.playPage]) { _ in
            return .audio([SourceBookAudioItem(url: Self.audio, headers: ["referer": "https://www.example.test/"])])
        }
        #expect(try await withReferer.resolve(Self.playPage)?.headers == ["referer": "https://www.example.test/"])

        let text: SiteBookPageAudioResolver = SiteBookPageAudioResolver(chapters: [Self.playPage]) { _ in
            return .text(title: nil, paragraphs: ["正文"])
        }
        await #expect(throws: BookPublicationContentError.unexpectedContent(chapterURL: Self.playPage)) {
            _ = try await text.resolve(Self.playPage)
        }
    }

    @Test func redirectedRequestKeepsRangeAndAddsMissingHeaders() throws {
        var request: HTTPRequest = HTTPRequest(url: try #require(HTTPURL(url: Self.playPage)))
        request.headers["Range"] = "bytes=0-1"
        let resolved: SiteBookResolvedAudio = SiteBookResolvedAudio(url: URL(string: "http://audio.example.test/a/1.m4a")!, headers: ["Referer": Self.playPage.absoluteString])
        let redirected: HTTPRequest = SiteBookAudioHTTPClient.upgradedToHTTPS(SiteBookAudioHTTPClient.redirected(request, to: resolved))
        #expect(redirected.url.url.absoluteString == "https://audio.example.test/a/1.m4a")
        #expect(redirected.headers["Range"] == "bytes=0-1")
        #expect(redirected.headers["Referer"] == Self.playPage.absoluteString)
    }

    // MARK: - Fixtures

    private static func detail(_ chapters: [URL]) -> SourceDetailOutput {
        return SourceDetailOutput(
            chapters: chapters.enumerated().map { index, url in SourceChapter(id: url.absoluteString, title: "\(index + 1)", url: url) },
            diagnostics: SourceRuntimeDiagnostics.skipped(message: "fixture")
        )
    }

    private static let audioReader: String = ##"{"id": "reader-1", "variant": "audio-media", "contentType": "audio", "request": {"needsWebView": true}, "media": {"item": {"selectorKind": "css", "function": "raw", "selector": "audio[src]"}, "url": {"selectorKind": "current", "function": "url", "param": "src"}}}"##
    private static let textReader: String = ##"{"id": "reader-1", "variant": "text-dom", "contentType": "text", "content": {"container": {"selectorKind": "css", "function": "raw", "selector": "#content"}, "segmentation": "lineBreaks"}}"##

    private static func source(reader: String) throws -> Source {
        let json: String = """
        {"version": 2, "name": "示例", "baseUrl": "https://www.example.test/",
         "site": {"name": "示例", "domain": "www.example.test", "baseURL": "https://www.example.test/"},
         "pages": [{"id": "page-list", "title": "列表", "type": "list", "url": "https://www.example.test/category/1",
                    "ruleRefs": {"list": "list-1", "detail": "detail-1", "reader": "reader-1"}}],
         "ruleSets": {
          "listRules": [{"id": "list-1", "url": "https://www.example.test/category/1", "type": "book",
           "itemRule": {"selectorKind": "css", "function": "raw", "selector": "li"},
           "fields": {"title": {"selectorKind": "css", "function": "text", "selector": "a"},
                      "detailURL": {"selectorKind": "css", "function": "url", "selector": "a", "param": "href"}}}],
          "detailRules": [{"id": "detail-1",
           "fields": {"title": {"selectorKind": "css", "function": "text", "selector": "h1"}},
           "chapterRule": {"item": {"selectorKind": "css", "function": "raw", "selector": "a.f"},
                           "title": {"selectorKind": "current", "function": "attr", "param": "ownText"},
                           "readerURL": {"selectorKind": "current", "function": "url", "param": "href"}}}],
          "readerRules": [\(reader)]
         }}
        """
        let rule: BookSiteRule = try JSONDecoder().decode(BookSiteRule.self, from: Data(json.utf8))
        return Source(
            id: "example",
            name: "示例",
            baseURL: "https://www.example.test/",
            type: .html,
            configuration: .book(BookSourceConfiguration(rule: rule)),
            enabled: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

private actor CallCounter {
    private(set) var value: Int = 0

    func increment() {
        self.value += 1
    }
}
