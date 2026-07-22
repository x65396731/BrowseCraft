import CloudKit
import CryptoKit
import Foundation

struct CloudKitRecordMapper: Sendable {
    static let zoneName: String = "BrowseCraftSync"
    static let sourceRecordType: String = "Source"
    static let favoriteItemRecordType: String = "FavoriteItem"

    let zoneID: CKRecordZone.ID

    init(zoneID: CKRecordZone.ID = CKRecordZone.ID(zoneName: Self.zoneName)) {
        self.zoneID = zoneID
    }

    func recordID(forSourceID sourceID: String) -> CKRecord.ID {
        return CKRecord.ID(
            recordName: Self.hashedRecordName(prefix: "source", components: [sourceID]),
            zoneID: self.zoneID
        )
    }

    func recordID(forFavoriteSourceID sourceID: String, itemID: String) -> CKRecord.ID {
        return CKRecord.ID(
            recordName: Self.hashedRecordName(
                prefix: "favorite",
                components: [sourceID, itemID]
            ),
            zoneID: self.zoneID
        )
    }

    func apply(_ payload: SourceCloudPayload, to record: CKRecord) throws {
        guard record.recordID == self.recordID(forSourceID: payload.sourceID) else {
            throw CloudKitRecordMappingError.recordIDMismatch
        }
        record["schemaVersion"] = NSNumber(value: payload.schemaVersion)
        record["sourceID"] = payload.sourceID as CKRecordValue
        record["name"] = payload.name as CKRecordValue
        record["baseURL"] = payload.baseURL as CKRecordValue
        record["type"] = payload.type as CKRecordValue
        record["kind"] = payload.kind as CKRecordValue
        record["configJSON"] = payload.configJSON as CKRecordValue
        record["enabled"] = NSNumber(value: payload.enabled)
        record["createdAt"] = payload.createdAt as CKRecordValue
        record["updatedAt"] = payload.updatedAt as CKRecordValue
        record["deletedAt"] = payload.deletedAt as CKRecordValue?
    }

    func apply(_ payload: FavoriteItemCloudPayload, to record: CKRecord) throws {
        guard record.recordID == self.recordID(
            forFavoriteSourceID: payload.sourceID,
            itemID: payload.itemID
        ) else {
            throw CloudKitRecordMappingError.recordIDMismatch
        }
        record["schemaVersion"] = NSNumber(value: payload.schemaVersion)
        record["itemID"] = payload.itemID as CKRecordValue
        record["sourceID"] = payload.sourceID as CKRecordValue
        record["kind"] = payload.kind as CKRecordValue
        record["title"] = payload.title as CKRecordValue
        record["detailURL"] = payload.detailURL as CKRecordValue
        record["coverURL"] = payload.coverURL as CKRecordValue?
        record["latestText"] = payload.latestText as CKRecordValue?
        record["itemMetadataJSON"] = payload.itemMetadataJSON as CKRecordValue
        record["sourceSnapshotJSON"] = payload.sourceSnapshotJSON as CKRecordValue?
        record["favoritedAt"] = payload.favoritedAt as CKRecordValue?
        record["updatedAt"] = payload.updatedAt as CKRecordValue
        record["deletedAt"] = payload.deletedAt as CKRecordValue?
    }

    func sourcePayload(from record: CKRecord) throws -> SourceCloudPayload {
        guard record.recordType == Self.sourceRecordType else {
            throw CloudKitRecordMappingError.unexpectedRecordType
        }
        let sourceID: String = try Self.required(record, key: "sourceID")
        guard record.recordID == self.recordID(forSourceID: sourceID) else {
            throw CloudKitRecordMappingError.recordIDMismatch
        }
        return SourceCloudPayload(
            schemaVersion: try Self.requiredInt(record, key: "schemaVersion"),
            userID: CloudAccountScope.localDefault.rawValue,
            sourceID: sourceID,
            name: try Self.required(record, key: "name"),
            baseURL: try Self.required(record, key: "baseURL"),
            type: try Self.required(record, key: "type"),
            kind: try Self.required(record, key: "kind"),
            configJSON: try Self.required(record, key: "configJSON"),
            enabled: try Self.requiredBool(record, key: "enabled"),
            createdAt: try Self.required(record, key: "createdAt"),
            updatedAt: try Self.required(record, key: "updatedAt"),
            deletedAt: record["deletedAt"] as? Date
        )
    }

    func favoriteItemPayload(from record: CKRecord) throws -> FavoriteItemCloudPayload {
        guard record.recordType == Self.favoriteItemRecordType else {
            throw CloudKitRecordMappingError.unexpectedRecordType
        }
        let itemID: String = try Self.required(record, key: "itemID")
        let sourceID: String = try Self.required(record, key: "sourceID")
        guard record.recordID == self.recordID(
            forFavoriteSourceID: sourceID,
            itemID: itemID
        ) else {
            throw CloudKitRecordMappingError.recordIDMismatch
        }
        return FavoriteItemCloudPayload(
            schemaVersion: try Self.requiredInt(record, key: "schemaVersion"),
            userID: CloudAccountScope.localDefault.rawValue,
            itemID: itemID,
            sourceID: sourceID,
            kind: try Self.required(record, key: "kind"),
            title: try Self.required(record, key: "title"),
            detailURL: try Self.required(record, key: "detailURL"),
            coverURL: record["coverURL"] as? String,
            latestText: record["latestText"] as? String,
            itemMetadataJSON: try Self.required(record, key: "itemMetadataJSON"),
            sourceSnapshotJSON: record["sourceSnapshotJSON"] as? String,
            favoritedAt: record["favoritedAt"] as? Date,
            updatedAt: try Self.required(record, key: "updatedAt"),
            deletedAt: record["deletedAt"] as? Date
        )
    }

    private static func required<T>(_ record: CKRecord, key: String) throws -> T {
        guard let value: T = record[key] as? T else {
            throw CloudKitRecordMappingError.missingField(path: key)
        }
        return value
    }

    private static func requiredInt(_ record: CKRecord, key: String) throws -> Int {
        guard let value: NSNumber = record[key] as? NSNumber else {
            throw CloudKitRecordMappingError.missingField(path: key)
        }
        return value.intValue
    }

    private static func requiredBool(_ record: CKRecord, key: String) throws -> Bool {
        guard let value: NSNumber = record[key] as? NSNumber else {
            throw CloudKitRecordMappingError.missingField(path: key)
        }
        return value.boolValue
    }

    /// 中文注释：CloudKit recordName 只使用固定长度 ASCII 摘要，原始业务 ID 仍保存在字段中校验。
    private static func hashedRecordName(prefix: String, components: [String]) -> String {
        let canonicalKey: String = components.map { component in
            return "\(component.utf8.count):\(component)"
        }.joined()
        let digest: SHA256.Digest = SHA256.hash(data: Data(canonicalKey.utf8))
        let hex: String = digest.map { String(format: "%02x", $0) }.joined()
        return "\(prefix):\(hex)"
    }
}

enum CloudKitRecordMappingError: Error, Hashable, Sendable, CustomStringConvertible {
    case unexpectedRecordType
    case recordIDMismatch
    case missingField(path: String)

    var description: String {
        switch self {
        case .unexpectedRecordType:
            return "Cloud record has unexpected type"
        case .recordIDMismatch:
            return "Cloud record identifier does not match payload"
        case .missingField(let path):
            return "Cloud record is missing field path=\(path)"
        }
    }
}
