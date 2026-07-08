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
struct FavoriteSourceSnapshot: Hashable, Codable {
    var id: String
    var name: String
    var baseURL: String
    var type: SourceType
    var configuration: SourceConfiguration
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(source: Source) {
        self.id = source.id
        self.name = source.name
        self.baseURL = source.baseURL
        self.type = source.type
        self.configuration = source.configuration
        self.enabled = source.enabled
        self.createdAt = source.createdAt
        self.updatedAt = source.updatedAt
    }

    func source() -> Source {
        return Source(
            id: self.id,
            name: self.name,
            baseURL: self.baseURL,
            type: self.type,
            configuration: self.configuration,
            enabled: self.enabled,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt
        )
    }
}
