import Foundation

// 中文注释：FavoriteContentItem 保存收藏页需要展示的内容快照。

enum FavoriteContentKind: String, Codable, Hashable {
    case rss
    case comic
    case videoNative
    case videoWeb
}

/// 中文注释：收藏页依赖这里的快照字段直接展示内容，不反查当前列表状态。
struct FavoriteContentItem: Identifiable, Hashable, Codable {
    var id: String
    var idCode: String? = nil
    var sourceID: String
    var title: String
    var detailURL: String
    var coverURL: String?
    var kind: FavoriteContentKind
    var latestText: String?
    var updatedAt: Date?
    var favoritedAt: Date?
    var listOrder: Int?
    var listContext: ListContext?
    var sourceSnapshot: FavoriteSourceSnapshot?

    func contentItem() -> ContentItem {
        let contentKind: SourceContentKind
        switch self.kind {
        case .rss:
            contentKind = .article
        case .comic:
            contentKind = .comic
        case .videoNative, .videoWeb:
            contentKind = .video
        }

        return ContentItem(
            id: self.id,
            idCode: self.idCode,
            sourceId: self.sourceID,
            title: self.title,
            detailURL: self.detailURL,
            coverURL: self.coverURL,
            type: contentKind,
            latestText: self.latestText,
            updatedAt: self.updatedAt,
            listOrder: self.listOrder,
            listContext: self.listContext
        )
    }

    func fallbackSource() -> Source? {
        return self.sourceSnapshot?.source()
    }

    var displayKindTitle: String {
        switch self.kind {
        case .rss:
            return "RSS"
        case .comic:
            return "Comic"
        case .videoNative:
            return "Native Video"
        case .videoWeb:
            return "Web Video"
        }
    }
}

/// 中文注释：收藏必须能独立打开详情，所以这里保存请求详情所需的 source 配置快照。
typealias FavoriteSourceSnapshot = SourceSnapshot
