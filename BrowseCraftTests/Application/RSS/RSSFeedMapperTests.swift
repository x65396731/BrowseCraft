import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：RSSFeedMapperTests 固定 P4.9.1 RSS 映射器的最小字段映射。
struct RSSFeedMapperTests {
    @Test func parsesRSSChannelAndItems() throws {
        let mapper: RSSFeedMapper = RSSFeedMapper()
        let feed: RSSFeed = try mapper.map(Self.solidotLikeRSS)

        #expect(feed.title == "Solidot")
        #expect(feed.items.count == 2)

        let first: RSSFeedItem = try #require(feed.items.first)
        #expect(first.title == "奇客资讯一")
        #expect(first.link?.absoluteString == "https://www.solidot.org/story?sid=100001")
        #expect(first.summary == "第一条摘要")
        #expect(first.guid == "solidot-100001")
        #expect(first.publishedAt != nil)
    }

    @Test func keepsMissingOptionalItemFieldsNil() throws {
        let mapper: RSSFeedMapper = RSSFeedMapper()
        let feed: RSSFeed = try mapper.map(Self.minimalRSS)
        let item: RSSFeedItem = try #require(feed.items.first)

        #expect(feed.title == nil)
        #expect(item.title == "Only title")
        #expect(item.link == nil)
        #expect(item.summary == nil)
        #expect(item.guid == nil)
        #expect(item.publishedAt == nil)
    }

    private static let solidotLikeRSS: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Solidot</title>
        <item>
          <title>奇客资讯一</title>
          <link>https://www.solidot.org/story?sid=100001</link>
          <description>第一条摘要</description>
          <pubDate>Sun, 05 Jul 2026 12:00:00 +0800</pubDate>
          <guid>solidot-100001</guid>
        </item>
        <item>
          <title>奇客资讯二</title>
          <link>https://www.solidot.org/story?sid=100002</link>
          <description>第二条摘要</description>
          <guid>solidot-100002</guid>
        </item>
      </channel>
    </rss>
    """

    private static let minimalRSS: String = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Only title</title>
        </item>
      </channel>
    </rss>
    """
}
