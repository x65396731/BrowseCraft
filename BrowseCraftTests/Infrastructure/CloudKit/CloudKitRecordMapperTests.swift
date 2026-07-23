import CloudKit
import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

struct CloudKitRecordMapperTests {
    @Test func detectsZoneNotFoundInsideCloudKitPartialFailure() {
        let zoneError: NSError = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.zoneNotFound.rawValue
        )
        let partialError: NSError = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [
                CKPartialErrorsByItemIDKey: [
                    "source-record": zoneError
                ]
            ]
        )
        let unrelatedError: NSError = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.networkUnavailable.rawValue
        )

        #expect(CKSyncEngineCloudRecordStore.containsZoneNotFound(zoneError))
        #expect(CKSyncEngineCloudRecordStore.containsZoneNotFound(partialError))
        #expect(CKSyncEngineCloudRecordStore.containsZoneNotFound(unrelatedError) == false)
    }

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
            recordID: mapper.recordID(
                forFavoriteSourceID: payload.sourceID,
                itemID: payload.itemID
            )
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

    @Test func recordNamesHashLongUnicodeBusinessIDsAndIncludeFavoriteSource() {
        let mapper: CloudKitRecordMapper = CloudKitRecordMapper()
        let longUnicodeItemID: String = String(repeating: "文章/🧭?token=value", count: 40)
        let sourceRecordID: CKRecord.ID = mapper.recordID(forSourceID: longUnicodeItemID)
        let firstFavoriteID: CKRecord.ID = mapper.recordID(
            forFavoriteSourceID: "source-a",
            itemID: longUnicodeItemID
        )
        let secondFavoriteID: CKRecord.ID = mapper.recordID(
            forFavoriteSourceID: "source-b",
            itemID: longUnicodeItemID
        )

        #expect(sourceRecordID.recordName.utf8.count < 255)
        #expect(sourceRecordID.recordName.utf8.allSatisfy { $0 < 128 })
        #expect(firstFavoriteID.recordName.utf8.count < 255)
        #expect(firstFavoriteID.recordName.utf8.allSatisfy { $0 < 128 })
        #expect(firstFavoriteID != secondFavoriteID)
        #expect(firstFavoriteID.recordName.contains(longUnicodeItemID) == false)
    }

    @Test func favoriteCloudSnapshotOmitsLocalIdentityAndRebindsTheCurrentScope() throws {
        let originalScope: String = "cloud:originating-device-scope"
        let currentScope: String = "cloud:current-device-scope"
        let source: Source = Self.makeRSSSource(userID: originalScope)
        let item: FavoriteContentItem = FavoriteContentItem(
            id: "favorite-1",
            sourceID: source.id,
            title: "Favorite",
            detailURL: "https://example.test/item",
            coverURL: nil,
            kind: .rss,
            latestText: nil,
            updatedAt: Date(timeIntervalSince1970: 2),
            favoritedAt: Date(timeIntervalSince1970: 3),
            listOrder: nil,
            listContext: nil,
            sourceSnapshot: FavoriteSourceSnapshot(source: source)
        )
        let localRecord: FavoriteItemRecord = try FavoriteItemRecord(
            userID: originalScope,
            item: item,
            updatedAt: Date(timeIntervalSince1970: 3),
            deletedAt: nil
        )
        var payload: FavoriteItemCloudPayload = try FavoriteItemCloudPayload(record: localRecord)
        let snapshotJSON: String = try #require(payload.sourceSnapshotJSON)
        let snapshotData: Data = try #require(snapshotJSON.data(using: .utf8))
        var snapshotObject: [String: Any] = try #require(
            JSONSerialization.jsonObject(with: snapshotData) as? [String: Any]
        )

        #expect(snapshotObject["userID"] == nil)
        #expect(snapshotObject["accountScope"] == nil)
        #expect(snapshotJSON.contains(originalScope) == false)

        // 中文注释：兼容已存在的旧开发记录，但绝不信任其中携带的本地身份。
        snapshotObject["userID"] = originalScope
        let legacyData: Data = try JSONSerialization.data(withJSONObject: snapshotObject)
        payload.sourceSnapshotJSON = try #require(String(data: legacyData, encoding: .utf8))
        payload.userID = currentScope

        let downloadedRecord: FavoriteItemRecord = try FavoriteItemRecord(payload: payload)

        #expect(downloadedRecord.userID == currentScope)
        #expect(downloadedRecord.favoriteItem()?.sourceSnapshot?.userID == currentScope)
    }

    private static func makeRSSSource(userID: String) -> Source {
        return Source(
            userID: userID,
            id: "source-1",
            name: "Source",
            baseURL: "https://example.test",
            type: .rss,
            configuration: .rss(
                RSSSourceConfiguration(
                    definition: RSSSourceDefinition(
                        feedURL: URL(string: "https://example.test/feed.xml")!,
                        requiresAccount: false,
                        refreshPolicy: .manual
                    )
                )
            ),
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }
}
