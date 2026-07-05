import Foundation

// 中文注释：RSSReadingHistory 保存用户进入过的 RSS 详情页快照。

/// 中文注释：History 页面读取该模型时应能直接显示内容，不依赖重新请求 RSS 网络数据。
struct RSSReadingHistory: Identifiable, Hashable {
    var id: String {
        return [
            self.userID,
            self.sourceID,
            self.itemID
        ].joined(separator: "::")
    }

    var userID: String
    var sourceID: String
    var itemID: String
    var dataType: SourceContentKind
    var title: String
    var dataContent: String
    /// 中文注释：RSS 条目自身的发布时间或更新时间；缺失时保存层应使用访问时间兜底。
    var dataTime: Date
    var visitedAt: Date
    var detailURL: URL?
    var sourceName: String?
    var originFeedURL: URL?
}
