import Foundation

// 中文注释：FavoriteItemCloudPayload 是单条收藏 item 的云端载荷。
struct FavoriteItemCloudPayload: Hashable, Codable, Sendable {
    static let currentSchemaVersion: Int = 1

    var schemaVersion: Int
    var userID: String
    var itemID: String
    var sourceID: String
    var kind: String
    var title: String
    var detailURL: String
    var coverURL: String?
    var latestText: String?
    var itemMetadataJSON: String
    var sourceSnapshotJSON: String?
    var favoritedAt: Date?
    var updatedAt: Date
    var deletedAt: Date?

    var lastChangedAt: Date {
        return max(self.updatedAt, self.deletedAt ?? .distantPast)
    }

    var isDeleted: Bool {
        return self.deletedAt != nil
    }
}

struct FavoriteItemCloudMetadata: Hashable, Codable {
    var idCode: String?
    var itemUpdatedAt: Date?
    var listOrder: Int?
    var listContext: ListContext?

    init(item: FavoriteContentItem) {
        self.idCode = item.idCode
        self.itemUpdatedAt = item.updatedAt
        self.listOrder = item.listOrder
        self.listContext = item.listContext
    }
}
