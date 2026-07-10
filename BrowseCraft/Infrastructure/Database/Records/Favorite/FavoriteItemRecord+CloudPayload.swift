import Foundation

extension FavoriteItemCloudPayload {
    init(record: FavoriteItemRecord) {
        self.schemaVersion = Self.currentSchemaVersion
        self.userID = record.userID
        self.itemID = record.itemID
        self.sourceID = record.sourceID
        self.kind = record.kind
        self.title = record.title
        self.detailURL = record.detailURL
        self.coverURL = record.coverURL
        self.latestText = record.latestText
        self.itemJSON = record.itemJSON
        self.sourceSnapshotJSON = record.sourceSnapshotJSON
        self.favoritedAt = record.favoritedAt
        self.updatedAt = record.updatedAt
        self.deletedAt = record.deletedAt
    }
}

extension FavoriteItemRecord {
    init(payload: FavoriteItemCloudPayload) {
        self.userID = payload.userID
        self.itemID = payload.itemID
        self.sourceID = payload.sourceID
        self.kind = payload.kind
        self.title = payload.title
        self.detailURL = payload.detailURL
        self.coverURL = payload.coverURL
        self.latestText = payload.latestText
        self.itemJSON = payload.itemJSON
        self.sourceSnapshotJSON = payload.sourceSnapshotJSON
        self.favoritedAt = payload.favoritedAt
        self.updatedAt = payload.updatedAt
        self.deletedAt = payload.deletedAt
        self.createdAt = payload.updatedAt
    }
}
