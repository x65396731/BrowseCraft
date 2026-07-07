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

    @Test func parsesAtomFeedEntries() throws {
        let mapper: RSSFeedMapper = RSSFeedMapper()
        let feed: RSSFeed = try mapper.map(Self.v2exLikeAtom)

        #expect(feed.title == "V2EX")
        #expect(feed.items.count == 2)

        let first: RSSFeedItem = try #require(feed.items.first)
        #expect(first.title == "[问与答] 开通 Apple Developer Program 受阻")
        #expect(first.link?.absoluteString == "https://www.v2ex.com/t/1225695#reply2")
        #expect(first.guid == "tag:www.v2ex.com,2026-07-07:/t/1225695")
        #expect(first.summary?.contains("Apple Developer Program") == true)
        #expect(first.coverURL?.absoluteString == "https://example.test/cover.png")
        #expect(first.publishedAt != nil)
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

    private static let v2exLikeAtom: String = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>V2EX</title>
      <link rel="alternate" type="text/html" href="https://www.v2ex.com/" />
      <link rel="self" type="application/atom+xml" href="https://www.v2ex.com/index.xml" />
      <id>https://www.v2ex.com/</id>
      <updated>2026-07-07T15:14:50Z</updated>
      <entry>
        <title>[问与答] 开通 Apple Developer Program 受阻</title>
        <link rel="alternate" type="text/html" href="https://www.v2ex.com/t/1225695#reply2" />
        <id>tag:www.v2ex.com,2026-07-07:/t/1225695</id>
        <published>2026-07-07T15:12:59Z</published>
        <updated>2026-07-07T15:14:50Z</updated>
        <content type="html"><![CDATA[
          <p>我的 AppleID 已经注册了 Apple Developer Program。</p>
          <img src="https://example.test/cover.png" />
        ]]></content>
      </entry>
      <entry>
        <title>[Claude] 刚才被 Claude 坑了</title>
        <link rel="alternate" type="text/html" href="https://www.v2ex.com/t/1225694#reply0" />
        <id>tag:www.v2ex.com,2026-07-07:/t/1225694</id>
        <updated>2026-07-07T15:12:45Z</updated>
        <content type="html">第二条摘要</content>
      </entry>
    </feed>
    """
}
