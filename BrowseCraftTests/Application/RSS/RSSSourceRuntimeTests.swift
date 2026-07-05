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
                feed: RSSFeed(
                    title: "Solidot",
                    items: [
                        RSSFeedItem(
                            title: "奇客资讯一",
                            link: try #require(URL(string: "https://www.solidot.org/story?sid=100001")),
                            summary: "第一条摘要",
                            publishedAt: nil,
                            guid: "solidot-100001"
                        ),
                        RSSFeedItem(
                            title: "奇客资讯二",
                            link: try #require(URL(string: "https://www.solidot.org/story?sid=100002")),
                            summary: nil,
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
        #expect(output.items[0].latestText == "第一条摘要")
        #expect(output.items[1].id == "https://www.solidot.org/story?sid=100002")
        #expect(output.pagination == nil)
        #expect(output.diagnostics.status == .succeeded)
    }

    @Test func capabilitiesOnlyAdvertiseRSSMVPListSupport() throws {
        let runtime: RSSSourceRuntime = RSSSourceRuntime(
            definition: try Self.rssDefinition(),
            feedLoader: StubRSSFeedLoader(feed: RSSFeed(title: "Solidot", items: []))
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
            feedLoader: StubRSSFeedLoader(feed: RSSFeed(title: "Solidot", items: []))
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

    private static func rssDefinition() throws -> SourceDefinition {
        return SourceDefinition(
            id: "rss.solidot",
            kind: .rss,
            name: "Solidot",
            baseURL: try #require(URL(string: "https://www.solidot.org")),
            version: nil,
            ownership: .user,
            rule: nil,
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
    var feed: RSSFeed

    func load(feedURL: URL) async throws -> RSSFeed {
        return self.feed
    }
}
