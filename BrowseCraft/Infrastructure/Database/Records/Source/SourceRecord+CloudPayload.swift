import Foundation

extension SourceCloudPayload {
    init(record: SourceRecord) {
        self.schemaVersion = Self.currentSchemaVersion
        self.userID = record.userID
        self.sourceID = record.id
        self.name = record.name
        self.baseURL = record.baseURL
        self.type = record.type
        self.kind = record.kind
        self.configJSON = record.configJSON
        self.enabled = record.enabled
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.deletedAt = record.deletedAt
    }
}

extension SourceRecord {
    init(payload: SourceCloudPayload) {
        self.init(
            userID: payload.userID,
            id: payload.sourceID,
            name: payload.name,
            baseURL: payload.baseURL,
            type: payload.type,
            kind: payload.kind,
            configJSON: payload.configJSON,
            enabled: payload.enabled,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            deletedAt: payload.deletedAt
        )
    }
}
