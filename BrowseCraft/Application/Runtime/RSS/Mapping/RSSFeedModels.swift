import Foundation

// 中文注释：RSSFeedModels 是 RSS runtime 内部模型，不进入 SiteRule 或规则编辑器。
struct RSSFeed: Equatable {
    var title: String?
    var items: [RSSFeedItem]
}

struct RSSFeedItem: Equatable {
    var title: String?
    var link: URL?
    var summary: String?
    var coverURL: URL?
    var media: RSSContentPayload.Media?
    var contentBlocks: [RSSContentPayload.Block]
    var publishedAt: Date?
    var guid: String?

    init(
        title: String?,
        link: URL?,
        summary: String?,
        coverURL: URL?,
        media: RSSContentPayload.Media? = nil,
        contentBlocks: [RSSContentPayload.Block] = [],
        publishedAt: Date?,
        guid: String?
    ) {
        self.title = title
        self.link = link
        self.summary = summary
        self.coverURL = coverURL
        self.media = media
        self.contentBlocks = contentBlocks
        self.publishedAt = publishedAt
        self.guid = guid
    }
}
