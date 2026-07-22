import Foundation

// 中文注释：FavoriteContentItem 保存收藏页需要展示的内容快照。

enum FavoriteContentKind: String, Codable, Hashable {
    case rss
    case comic
    case videoNative
    case videoWeb
}

/// 中文注释：收藏的业务身份必须同时包含来源和来源内条目 ID，不能假定不同来源的 GUID/link 全局唯一。
struct FavoriteItemIdentity: Hashable, Codable, Sendable {
    let sourceID: String
    let itemID: String

    /// 中文注释：同步队列需要可逆键，以便从队列精确找回复合主键对应的本地记录。
    var syncEntityID: String {
        let sourceByteCount: Int = self.sourceID.utf8.count
        return "\(sourceByteCount):\(self.sourceID)\(self.itemID)"
    }

    init(sourceID: String, itemID: String) {
        self.sourceID = sourceID
        self.itemID = itemID
    }

    init?(syncEntityID: String) {
        guard let separator: String.Index = syncEntityID.firstIndex(of: ":"),
              let sourceByteCount: Int = Int(syncEntityID[..<separator]),
              sourceByteCount >= 0 else {
            return nil
        }
        let payloadStart: String.Index = syncEntityID.index(after: separator)
        let payloadData: Data = Data(syncEntityID[payloadStart...].utf8)
        guard payloadData.count >= sourceByteCount,
              let sourceID: String = String(
                data: Data(payloadData.prefix(sourceByteCount)),
                encoding: .utf8
              ),
              let itemID: String = String(
                data: Data(payloadData.dropFirst(sourceByteCount)),
                encoding: .utf8
              ) else {
            return nil
        }
        self.init(sourceID: sourceID, itemID: itemID)
    }
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

    var identity: FavoriteItemIdentity {
        return FavoriteItemIdentity(sourceID: self.sourceID, itemID: self.id)
    }

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
