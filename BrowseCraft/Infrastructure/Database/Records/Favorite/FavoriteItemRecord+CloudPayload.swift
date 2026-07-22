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
        self.sourceSnapshotJSON = try Self.encodeCloudSourceSnapshot(item.sourceSnapshot)
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
                  let cloudSnapshot: FavoriteSourceCloudSnapshot = try? JSONDecoder().decode(
                    FavoriteSourceCloudSnapshot.self,
                    from: snapshotData
                  ) else {
                throw FavoriteItemCloudPayloadConversionError.invalidSourceSnapshot
            }
            sourceSnapshot = cloudSnapshot.localSnapshot(userID: payload.userID)
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

private extension FavoriteItemCloudPayload {
    static func encodeCloudSourceSnapshot(
        _ snapshot: FavoriteSourceSnapshot?
    ) throws -> String? {
        guard let snapshot: FavoriteSourceSnapshot else {
            return nil
        }
        let cloudSnapshot: FavoriteSourceCloudSnapshot = FavoriteSourceCloudSnapshot(
            snapshot: snapshot
        )
        let data: Data = try JSONEncoder().encode(cloudSnapshot)
        guard let json: String = String(data: data, encoding: .utf8) else {
            throw FavoriteItemCloudPayloadConversionError.invalidSourceSnapshot
        }
        return json
    }
}

/// 中文注释：CloudKit 快照不包含本地 userID/account scope；下载后只绑定当前已确认分区。
private struct FavoriteSourceCloudSnapshot: Codable {
    var id: String
    var name: String
    var baseURL: String
    var type: SourceType
    var configuration: SourceConfiguration
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(snapshot: FavoriteSourceSnapshot) {
        self.id = snapshot.id
        self.name = snapshot.name
        self.baseURL = snapshot.baseURL
        self.type = snapshot.type
        self.configuration = snapshot.configuration
        self.enabled = snapshot.enabled
        self.createdAt = snapshot.createdAt
        self.updatedAt = snapshot.updatedAt
        self.deletedAt = snapshot.deletedAt
    }

    func localSnapshot(userID: String) -> FavoriteSourceSnapshot {
        return FavoriteSourceSnapshot(
            source: Source(
                userID: userID,
                id: self.id,
                name: self.name,
                baseURL: self.baseURL,
                type: self.type,
                configuration: self.configuration,
                enabled: self.enabled,
                createdAt: self.createdAt,
                updatedAt: self.updatedAt,
                deletedAt: self.deletedAt
            )
        )
    }
}

private enum FavoriteItemCloudPayloadConversionError: Error {
    case invalidLocalItemJSON
    case invalidCloudMetadata
    case invalidSourceSnapshot
}
