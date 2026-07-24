import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：RSSSourceRuntimeTests 固定 P4.9.3 RSS runtime 的 loadList 映射和能力边界。
struct RSSSourceRuntimeTests {
    @Test func loadListMapsRSSItemsToSourceContentItems() async throws {
        let definition: SourceDefinition = try Self.rssDefinition()
        let runtime: RSSSourceRuntime = RSSSourceRuntime(
            definition: definition,
            feedLoader: StubRSSFeedLoader(
                feed: BrowseCraft.RSSFeed(
                    title: "Solidot",
                    items: [
                        BrowseCraft.RSSFeedItem(
                            title: "奇客资讯一",
                            link: try #require(URL(string: "https://www.solidot.org/story?sid=100001")),
                            summary: "第一条摘要",
                            coverURL: try #require(URL(string: "https://www.solidot.org/image.jpg")),
                            publishedAt: nil,
                            guid: "solidot-100001"
                        ),
                        BrowseCraft.RSSFeedItem(
                            title: "奇客资讯二",
                            link: try #require(URL(string: "https://www.solidot.org/story?sid=100002")),
                            summary: nil,
                            coverURL: nil,
                            publishedAt: Date(timeIntervalSince1970: 1_783_209_600),
                            guid: nil
                        )
                    ]
                )
            )
        )

        let output: SourceListOutput = try await runtime.loadList(
            SourceListInput(
                page: 1,
                urlOverride: nil,
                context: Self.context(sourceID: definition.id)
            )
        )

        #expect(output.items.count == 2)
        #expect(output.items[0].id == "solidot-100001")
        #expect(output.items[0].title == "奇客资讯一")
        #expect(output.items[0].detailURL?.absoluteString == "https://www.solidot.org/story?sid=100001")
        #expect(output.items[0].coverURL?.absoluteString == "https://www.solidot.org/image.jpg")
        #expect(output.items[0].latestText == "第一条摘要")
        #expect(output.items[1].id == "https://www.solidot.org/story?sid=100002")
        #expect(output.pagination == nil)
        #expect(output.diagnostics.status == .succeeded)
    }

    @Test func capabilitiesOnlyAdvertiseRSSMVPListSupport() throws {
        let runtime: RSSSourceRuntime = RSSSourceRuntime(
            definition: try Self.rssDefinition(),
            feedLoader: StubRSSFeedLoader(feed: BrowseCraft.RSSFeed(title: "Solidot", items: []))
        )

        #expect(runtime.capabilities.supportsSearch == false)
        #expect(runtime.capabilities.supportsPagination == false)
        #expect(runtime.capabilities.supportsDetail == false)
        #expect(runtime.capabilities.supportsReader == false)
        #expect(runtime.capabilities.supportsDebug == false)
        #expect(runtime.capabilities.requiresWebView == false)
        #expect(runtime.capabilities.requiresCookieStore == false)
        #expect(runtime.capabilities.requiresAccount == false)
        #expect(runtime.capabilities.limitations.isEmpty == false)
    }

    @Test func loadListRejectsSourceMismatch() async throws {
        let runtime: RSSSourceRuntime = RSSSourceRuntime(
            definition: try Self.rssDefinition(),
            feedLoader: StubRSSFeedLoader(feed: BrowseCraft.RSSFeed(title: "Solidot", items: []))
        )

        do {
            _ = try await runtime.loadList(
                SourceListInput(
                    page: 1,
                    urlOverride: nil,
                    context: Self.context(sourceID: "other.source")
                )
            )
            Issue.record("Expected RSS runtime to reject source mismatch.")
        } catch SourceRuntimeError.sourceMismatch(let expected, let actual) {
            #expect(expected == "rss.solidot")
            #expect(actual == "other.source")
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func loadListMapsStandardMediaIntoCoreRichContent() async throws {
        let definition: SourceDefinition = try Self.rssDefinition()
        let runtime: RSSSourceRuntime = RSSSourceRuntime(
            definition: definition,
            feedLoader: StubRSSFeedLoader(
                feed: BrowseCraft.RSSFeed(
                    title: "Podcast",
                    items: [
                        BrowseCraft.RSSFeedItem(
                            title: "Audio",
                            link: try #require(URL(string: "https://example.test/audio")),
                            summary: "Episode summary",
                            coverURL: try #require(URL(string: "https://example.test/poster.jpg")),
                            media: RSSContentPayload.Media(
                                kind: .audio,
                                playbackMode: .directMedia,
                                url: "https://media.example.test/audio.mp3",
                                mimeType: "audio/mpeg",
                                duration: "12:34",
                                posterURL: nil,
                                sourcePageURL: nil
                            ),
                            publishedAt: nil,
                            guid: "audio-1"
                        )
                    ]
                )
            )
        )

        let output: SourceListOutput = try await runtime.loadList(
            SourceListInput(
                page: 1,
                urlOverride: nil,
                context: Self.context(sourceID: definition.id)
            )
        )

        let payload: RSSContentPayload = try #require(output.items.first?.richContent)
        #expect(output.items.first?.latestText == "Episode summary")
        #expect(payload.summary == "Episode summary")
        #expect(payload.media?.kind == .audio)
        #expect(payload.media?.playbackMode == .directMedia)
        #expect(payload.media?.url == "https://media.example.test/audio.mp3")
        #expect(payload.media?.mimeType == "audio/mpeg")
        #expect(payload.media?.duration == "12:34")
        #expect(payload.media?.posterURL == "https://example.test/poster.jpg")
        #expect(payload.media?.sourcePageURL == "https://example.test/audio")
    }

    @Test func loadListClassifiesKnownPlaybackPageLinksWithoutDedicatedRSSSource() async throws {
        let definition: SourceDefinition = try Self.rssDefinition()
        let runtime: RSSSourceRuntime = RSSSourceRuntime(
            definition: definition,
            feedLoader: StubRSSFeedLoader(
                feed: BrowseCraft.RSSFeed(
                    title: "Mixed links",
                    items: [
                        BrowseCraft.RSSFeedItem(
                            title: "Known audio page",
                            link: try #require(URL(string: "https://www.gcores.com/radios/216726")),
                            summary: "Radio summary",
                            coverURL: try #require(URL(string: "https://image.gcores.com/radio.jpg")),
                            publishedAt: nil,
                            guid: "radio"
                        ),
                        BrowseCraft.RSSFeedItem(
                            title: "Known video page",
                            link: try #require(URL(string: "https://www.gcores.com/videos/217000")),
                            summary: "Video summary",
                            coverURL: nil,
                            publishedAt: nil,
                            guid: "video"
                        ),
                        BrowseCraft.RSSFeedItem(
                            title: "Known article page",
                            link: try #require(URL(string: "https://www.gcores.com/articles/216999")),
                            summary: "Article summary",
                            coverURL: nil,
                            publishedAt: nil,
                            guid: "article"
                        )
                    ]
                )
            )
        )

        let output: SourceListOutput = try await runtime.loadList(
            SourceListInput(
                page: 1,
                urlOverride: nil,
                context: Self.context(sourceID: definition.id)
            )
        )

        let radioPayload: RSSContentPayload = try #require(output.items[0].richContent)
        #expect(radioPayload.media?.kind == .audio)
        #expect(radioPayload.media?.playbackMode == .webPage)
        #expect(radioPayload.media?.url == "https://www.gcores.com/radios/216726")
        #expect(radioPayload.media?.posterURL == "https://image.gcores.com/radio.jpg")

        let videoPayload: RSSContentPayload = try #require(output.items[1].richContent)
        #expect(videoPayload.media?.kind == .video)
        #expect(videoPayload.media?.playbackMode == .webPage)
        #expect(videoPayload.media?.url == "https://www.gcores.com/videos/217000")

        #expect(output.items[2].richContent == nil)
        #expect(output.items[2].latestText == "Article summary")
    }

    private static func rssDefinition() throws -> SourceDefinition {
        return SourceDefinition(
            id: "rss.solidot",
            runtimeKind: .rss,
            name: "Solidot",
            baseURL: try #require(URL(string: "https://www.solidot.org")),
            version: nil,
            ownership: .user,
            comic: nil,
            rss: RSSSourceDefinition(
                feedURL: try #require(URL(string: "https://www.solidot.org/index.rss")),
                requiresAccount: false,
                refreshPolicy: .manual
            ),
            plugin: nil
        )
    }

    private static func context(sourceID: String) -> SourceRuntimeContext {
        return SourceRuntimeContext(
            sourceID: sourceID,
            pageID: nil,
            tabID: nil,
            ruleID: nil,
            requestOverride: nil,
            debugMode: false,
            operation: .list
        )
    }
}

private struct StubRSSFeedLoader: RSSFeedLoading {
    var feed: BrowseCraft.RSSFeed

    func load(feedURL: URL) async throws -> BrowseCraft.RSSFeed {
        return self.feed
    }
}
