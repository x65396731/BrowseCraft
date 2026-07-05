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
    var publishedAt: Date?
    var guid: String?
}
