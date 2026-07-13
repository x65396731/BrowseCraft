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

    @Test func parsesRichContentBlocksFromEncodedHTML() throws {
        let mapper: RSSFeedMapper = RSSFeedMapper()
        let feed: RSSFeed = try mapper.map(Self.richRSS)
        let item: RSSFeedItem = try #require(feed.items.first)
        let secondItem: RSSFeedItem = try #require(feed.items.dropFirst().first)

        #expect(feed.items.count == 2)
        #expect(item.coverURL?.absoluteString == "https://example.test/one.jpg")
        #expect(item.contentBlocks.map(\.kind) == [.subtitle, .paragraph, .image, .subtitle, .paragraph, .image])
        #expect(item.contentBlocks[0].text == "第一节")
        #expect(item.contentBlocks[1].text == "第一段正文")
        #expect(item.contentBlocks[2].imageURL == "https://example.test/one.jpg")
        #expect(item.contentBlocks[3].text == "ROG二十周年展示区：典藏之巅，致敬传奇")
        #expect(item.contentBlocks[4].text == "第二段正文")
        #expect(item.contentBlocks[5].imageURL == "https://example.test/two.jpg")

        #expect(secondItem.contentBlocks.map(\.kind) == [.subtitle, .paragraph, .image])
        #expect(secondItem.contentBlocks[0].text == "第二条标题")
        #expect(secondItem.contentBlocks[1].text == "第二条正文")
        #expect(secondItem.contentBlocks[2].imageURL == "https://example.test/three.jpg")
    }

    @Test func parsesRSSAudioAndVideoEnclosuresWithoutBreakingImageCovers() throws {
        let mapper: RSSFeedMapper = RSSFeedMapper()
        let feed: RSSFeed = try mapper.map(Self.mediaEnclosureRSS)

        #expect(feed.items.count == 4)

        let audioItem: RSSFeedItem = try #require(feed.items.first)
        #expect(audioItem.media?.kind == .audio)
        #expect(audioItem.media?.playbackMode == .directMedia)
        #expect(audioItem.media?.url == "https://media.example.test/show.mp3")
        #expect(audioItem.media?.mimeType == "audio/mpeg")
        #expect(audioItem.media?.duration == "01:02:03")
        #expect(audioItem.coverURL?.absoluteString == "https://media.example.test/show.jpg")
        #expect(audioItem.media?.posterURL == "https://media.example.test/show.jpg")

        let videoItem: RSSFeedItem = try #require(feed.items.dropFirst().first)
        #expect(videoItem.media?.kind == .video)
        #expect(videoItem.media?.playbackMode == .directMedia)
        #expect(videoItem.media?.url == "https://media.example.test/movie.mp4")
        #expect(videoItem.media?.mimeType == "video/mp4")

        let imageItem: RSSFeedItem = try #require(feed.items.dropFirst(2).first)
        #expect(imageItem.coverURL?.absoluteString == "https://media.example.test/cover.jpg")
        #expect(imageItem.media == nil)

        let unknownItem: RSSFeedItem = try #require(feed.items.dropFirst(3).first)
        #expect(unknownItem.coverURL == nil)
        #expect(unknownItem.media == nil)
    }

    @Test func parsesAtomEnclosureAsMediaAndKeepsAlternateLink() throws {
        let mapper: RSSFeedMapper = RSSFeedMapper()
        let feed: RSSFeed = try mapper.map(Self.atomMediaFeed)
        let item: RSSFeedItem = try #require(feed.items.first)

        #expect(item.link?.absoluteString == "https://example.test/posts/one")
        #expect(item.media?.kind == .audio)
        #expect(item.media?.playbackMode == .directMedia)
        #expect(item.media?.url == "https://media.example.test/one.m4a")
        #expect(item.media?.mimeType == "audio/mp4")
    }

    @Test func parsesMediaRSSContentPlayerAndThumbnail() throws {
        let mapper: RSSFeedMapper = RSSFeedMapper()
        let feed: RSSFeed = try mapper.map(Self.mediaRSS)

        let directVideoItem: RSSFeedItem = try #require(feed.items.first)
        #expect(directVideoItem.coverURL?.absoluteString == "https://media.example.test/poster.jpg")
        #expect(directVideoItem.media?.kind == .video)
        #expect(directVideoItem.media?.playbackMode == .directMedia)
        #expect(directVideoItem.media?.url == "https://media.example.test/stream.m3u8")
        #expect(directVideoItem.media?.mimeType == "application/vnd.apple.mpegurl")
        #expect(directVideoItem.media?.duration == "1200")
        #expect(directVideoItem.media?.posterURL == "https://media.example.test/poster.jpg")

        let playerItem: RSSFeedItem = try #require(feed.items.dropFirst().first)
        #expect(playerItem.media?.kind == .video)
        #expect(playerItem.media?.playbackMode == .webPage)
        #expect(playerItem.media?.url == "https://player.example.test/watch/1")
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

    private static let richRSS: String = """
    <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
      <channel>
        <item>
          <title>富内容</title>
          <content:encoded><![CDATA[
            <h2>第一节</h2>
            <p>第一段正文</p>
            <img src="https://example.test/one.jpg" />
            <p><strong>ROG二十周年展示区：典藏之巅，致敬传奇</strong></p>
            <p>第二段正文<img src="https://example.test/two.jpg" /></p>
          ]]></content:encoded>
        </item>
        <item>
          <title>第二条富内容</title>
          <content:encoded><![CDATA[
            <p><strong>第二条标题</strong></p>
            <p>第二条正文</p>
            <img src="https://example.test/three.jpg" />
          ]]></content:encoded>
        </item>
      </channel>
    </rss>
    """

    private static let mediaEnclosureRSS: String = """
    <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
      <channel>
        <item>
          <title>Audio episode</title>
          <link>https://example.test/audio</link>
          <itunes:image href="https://media.example.test/show.jpg" />
          <itunes:duration>01:02:03</itunes:duration>
          <enclosure url="https://media.example.test/show.mp3" type="audio/mpeg" />
        </item>
        <item>
          <title>Video episode</title>
          <link>https://example.test/video</link>
          <enclosure url="https://media.example.test/movie.mp4" />
        </item>
        <item>
          <title>Image enclosure</title>
          <enclosure url="https://media.example.test/cover.jpg" type="image/jpeg" />
        </item>
        <item>
          <title>Unknown enclosure</title>
          <enclosure url="https://media.example.test/file.bin" type="application/octet-stream" />
        </item>
      </channel>
    </rss>
    """

    private static let atomMediaFeed: String = """
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Atom Media</title>
      <entry>
        <title>Atom audio</title>
        <link rel="alternate" type="text/html" href="https://example.test/posts/one" />
        <link rel="enclosure" type="audio/mp4" href="https://media.example.test/one.m4a" />
        <id>tag:example.test,2026:one</id>
      </entry>
    </feed>
    """

    private static let mediaRSS: String = """
    <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
      <channel>
        <item>
          <title>Media RSS video</title>
          <media:group>
            <media:thumbnail url="https://media.example.test/poster.jpg" />
            <media:content url="https://media.example.test/stream.m3u8" type="application/vnd.apple.mpegurl" duration="1200" />
          </media:group>
        </item>
        <item>
          <title>Media RSS player</title>
          <media:player url="https://player.example.test/watch/1" />
        </item>
      </channel>
    </rss>
    """
}
