import CloudKit
import Foundation
import Testing
@testable import BrowseCraft

struct CloudKitRecordMapperTests {
    @Test func sourceRoundTripDoesNotStoreLocalAccountIdentity() throws {
        let mapper: CloudKitRecordMapper = CloudKitRecordMapper()
        let payload: SourceCloudPayload = SourceCloudPayload(
            schemaVersion: 1,
            userID: "cloud:private-local-scope",
            sourceID: "source-1",
            name: "Source",
            baseURL: "https://example.test",
            type: "rss",
            kind: "rss",
            configJSON: "{}",
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            deletedAt: nil
        )
        let record: CKRecord = CKRecord(
            recordType: CloudKitRecordMapper.sourceRecordType,
            recordID: mapper.recordID(forSourceID: payload.sourceID)
        )

        try mapper.apply(payload, to: record)
        let restored: SourceCloudPayload = try mapper.sourcePayload(from: record)

        #expect(record["userID"] == nil)
        #expect(record["accountScope"] == nil)
        #expect(restored.sourceID == payload.sourceID)
        #expect(restored.configJSON == payload.configJSON)
    }

    @Test func favoriteRoundTripUsesItemMetadataField() throws {
        let mapper: CloudKitRecordMapper = CloudKitRecordMapper()
        let payload: FavoriteItemCloudPayload = FavoriteItemCloudPayload(
            schemaVersion: 1,
            userID: "cloud:private-local-scope",
            itemID: "favorite-1",
            sourceID: "source-1",
            kind: FavoriteContentKind.rss.rawValue,
            title: "Favorite",
            detailURL: "https://example.test/item",
            coverURL: nil,
            latestText: nil,
            itemMetadataJSON: "{\"listOrder\":1}",
            sourceSnapshotJSON: nil,
            favoritedAt: nil,
            updatedAt: Date(timeIntervalSince1970: 2),
            deletedAt: nil
        )
        let record: CKRecord = CKRecord(
            recordType: CloudKitRecordMapper.favoriteItemRecordType,
            recordID: mapper.recordID(forFavoriteItemID: payload.itemID)
        )

        try mapper.apply(payload, to: record)
        let restored: FavoriteItemCloudPayload = try mapper.favoriteItemPayload(from: record)

        #expect(record["itemJSON"] == nil)
        #expect(record["itemMetadataJSON"] as? String == payload.itemMetadataJSON)
        #expect(restored.itemID == payload.itemID)
    }

    @Test func downloadRejectsRecordNameAndBusinessIDMismatch() throws {
        let mapper: CloudKitRecordMapper = CloudKitRecordMapper()
        let record: CKRecord = CKRecord(
            recordType: CloudKitRecordMapper.sourceRecordType,
            recordID: mapper.recordID(forSourceID: "source-1")
        )
        record["schemaVersion"] = NSNumber(value: 1)
        record["sourceID"] = "source-2" as CKRecordValue

        #expect(throws: CloudKitRecordMappingError.recordIDMismatch) {
            _ = try mapper.sourcePayload(from: record)
        }
    }
}
