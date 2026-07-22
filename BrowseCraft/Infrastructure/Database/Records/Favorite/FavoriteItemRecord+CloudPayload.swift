import Foundation

extension FavoriteItemCloudPayload {
    init(record: FavoriteItemRecord) throws {
        guard let item: FavoriteContentItem = record.favoriteItem() else {
            throw FavoriteItemCloudPayloadConversionError.invalidLocalItemJSON
        }
        let metadataData: Data = try JSONEncoder().encode(FavoriteItemCloudMetadata(item: item))

        self.schemaVersion = Self.currentSchemaVersion
        self.userID = record.userID
        self.itemID = record.itemID
        self.sourceID = record.sourceID
        self.kind = record.kind
        self.title = record.title
        self.detailURL = record.detailURL
        self.coverURL = record.coverURL
        self.latestText = record.latestText
        self.itemMetadataJSON = String(data: metadataData, encoding: .utf8) ?? "{}"
        self.sourceSnapshotJSON = record.sourceSnapshotJSON
        self.favoritedAt = record.favoritedAt
        self.updatedAt = record.updatedAt
        self.deletedAt = record.deletedAt
    }
}

extension FavoriteItemRecord {
    init(payload: FavoriteItemCloudPayload) throws {
        guard let kind: FavoriteContentKind = FavoriteContentKind(rawValue: payload.kind),
              let metadataData: Data = payload.itemMetadataJSON.data(using: .utf8),
              let metadata: FavoriteItemCloudMetadata = try? JSONDecoder().decode(
                FavoriteItemCloudMetadata.self,
                from: metadataData
              ) else {
            throw FavoriteItemCloudPayloadConversionError.invalidCloudMetadata
        }

        var sourceSnapshot: FavoriteSourceSnapshot?
        if let snapshotJSON: String = payload.sourceSnapshotJSON {
            guard let snapshotData: Data = snapshotJSON.data(using: .utf8),
                  let decodedSnapshot: FavoriteSourceSnapshot = try? JSONDecoder().decode(
                    FavoriteSourceSnapshot.self,
                    from: snapshotData
                  ) else {
                throw FavoriteItemCloudPayloadConversionError.invalidSourceSnapshot
            }
            sourceSnapshot = decodedSnapshot
        }

        let item: FavoriteContentItem = FavoriteContentItem(
            id: payload.itemID,
            idCode: metadata.idCode,
            sourceID: payload.sourceID,
            title: payload.title,
            detailURL: payload.detailURL,
            coverURL: payload.coverURL,
            kind: kind,
            latestText: payload.latestText,
            updatedAt: metadata.itemUpdatedAt,
            favoritedAt: payload.favoritedAt,
            listOrder: metadata.listOrder,
            listContext: metadata.listContext,
            sourceSnapshot: sourceSnapshot
        )
        try self.init(
            userID: payload.userID,
            item: item,
            updatedAt: payload.updatedAt,
            deletedAt: payload.deletedAt
        )
    }
}

private enum FavoriteItemCloudPayloadConversionError: Error {
    case invalidLocalItemJSON
    case invalidCloudMetadata
    case invalidSourceSnapshot
}
