import Foundation
@testable import BrowseCraft

struct SourceCloudRecord: Hashable {
    var payload: SourceCloudPayload
    var serverUpdatedAt: Date
    var version: Int
}

struct FavoriteItemCloudRecord: Hashable {
    var payload: FavoriteItemCloudPayload
    var serverUpdatedAt: Date
    var version: Int
}

// 中文注释：MockCloudRecordStore 模拟 CloudKit 的增量 token、保存失败和服务端版本。
final class MockCloudRecordStore: CloudRecordStore, @unchecked Sendable {
    private var sourceRecordsByID: [String: SourceCloudRecord]
    private var favoriteItemRecordsByID: [FavoriteItemIdentity: FavoriteItemCloudRecord]
    private var currentVersion: Int
    private let now: () -> Date
    private let eventLock: NSLock = NSLock()
    private var recordedEvents: [String] = []

    var failNextFetch: Bool
    var failNextSave: Bool
    var nextSourceSaveFailureIDs: Set<String>
    var nextFavoriteItemSaveFailureIDs: Set<String>

    init(
        sourceRecords: [SourceCloudRecord] = [],
        favoriteItemRecords: [FavoriteItemCloudRecord] = [],
        now: @escaping () -> Date = Date.init
    ) {
        self.sourceRecordsByID = Dictionary(
            uniqueKeysWithValues: sourceRecords.map { record in
                return (record.payload.sourceID, record)
            }
        )
        self.favoriteItemRecordsByID = Dictionary(
            uniqueKeysWithValues: favoriteItemRecords.map { record in
                return (record.payload.identity, record)
            }
        )
        self.currentVersion = (sourceRecords.map(\.version) + favoriteItemRecords.map(\.version)).max() ?? 0
        self.now = now
        self.failNextFetch = false
        self.failNextSave = false
        self.nextSourceSaveFailureIDs = []
        self.nextFavoriteItemSaveFailureIDs = []
    }

    func fetchChangedSourceRecords(since token: Data?) async throws -> SourceCloudChangeSet {
        self.recordEvent("sourceFetch")
        if self.failNextFetch {
            self.failNextFetch = false
            throw MockCloudRecordStoreError.fetchFailed
        }

        let tokenVersion: Int = Self.version(from: token)
        let records: [SourceCloudPayload] = self.sourceRecordsByID.values
            .filter { record in
                return record.version > tokenVersion
            }
            .sorted { lhs, rhs in
                if lhs.version != rhs.version {
                    return lhs.version < rhs.version
                }

                return lhs.payload.sourceID < rhs.payload.sourceID
            }
            .map(\.payload)

        return SourceCloudChangeSet(
            records: records,
            changeToken: Self.tokenData(for: self.currentVersion)
        )
    }

    func saveSourceRecords(
        _ records: [SourceCloudPayload]
    ) async throws -> CloudRecordBatchSaveResult {
        self.recordEvent("sourceSave")
        if self.failNextSave {
            self.failNextSave = false
            throw MockCloudRecordStoreError.saveFailed
        }

        let failedIDs: Set<String> = self.nextSourceSaveFailureIDs
        self.nextSourceSaveFailureIDs = []
        let savedRecords: [SourceCloudPayload] = records.filter {
            $0.isBuiltIn == false && failedIDs.contains($0.sourceID) == false
        }
        for payload: SourceCloudPayload in savedRecords {
            self.currentVersion += 1
            self.sourceRecordsByID[payload.sourceID] = SourceCloudRecord(
                payload: payload,
                serverUpdatedAt: self.now(),
                version: self.currentVersion
            )
        }
        return CloudRecordBatchSaveResult(
            savedEntityIDs: Set(savedRecords.map(\.sourceID)),
            failures: failedIDs.map {
                CloudRecordSaveFailure(entityID: $0, code: "mockPartialFailure", retryAfter: 1)
            }
        )
    }

    func fetchChangedFavoriteItemRecords(since token: Data?) async throws -> FavoriteItemCloudChangeSet {
        self.recordEvent("favoriteFetch")
        if self.failNextFetch {
            self.failNextFetch = false
            throw MockCloudRecordStoreError.fetchFailed
        }

        let tokenVersion: Int = Self.version(from: token)
        let records: [FavoriteItemCloudPayload] = self.favoriteItemRecordsByID.values
            .filter { record in
                return record.version > tokenVersion
            }
            .sorted { lhs, rhs in
                if lhs.version != rhs.version {
                    return lhs.version < rhs.version
                }
                if lhs.payload.sourceID != rhs.payload.sourceID {
                    return lhs.payload.sourceID < rhs.payload.sourceID
                }
                return lhs.payload.itemID < rhs.payload.itemID
            }
            .map(\.payload)

        return FavoriteItemCloudChangeSet(
            records: records,
            changeToken: Self.tokenData(for: self.currentVersion)
        )
    }

    func saveFavoriteItemRecords(
        _ records: [FavoriteItemCloudPayload]
    ) async throws -> CloudRecordBatchSaveResult {
        self.recordEvent("favoriteSave")
        if self.failNextSave {
            self.failNextSave = false
            throw MockCloudRecordStoreError.saveFailed
        }

        let failedIDs: Set<String> = self.nextFavoriteItemSaveFailureIDs
        self.nextFavoriteItemSaveFailureIDs = []
        let failedRecords: [FavoriteItemCloudPayload] = records.filter {
            failedIDs.contains($0.itemID) || failedIDs.contains($0.identity.syncEntityID)
        }
        let savedRecords: [FavoriteItemCloudPayload] = records.filter {
            failedIDs.contains($0.itemID) == false &&
                failedIDs.contains($0.identity.syncEntityID) == false
        }
        for payload: FavoriteItemCloudPayload in savedRecords {
            self.currentVersion += 1
            self.favoriteItemRecordsByID[payload.identity] = FavoriteItemCloudRecord(
                payload: payload,
                serverUpdatedAt: self.now(),
                version: self.currentVersion
            )
        }
        return CloudRecordBatchSaveResult(
            savedEntityIDs: Set(savedRecords.map { $0.identity.syncEntityID }),
            failures: failedRecords.map { payload in
                CloudRecordSaveFailure(
                    entityID: payload.identity.syncEntityID,
                    code: "mockPartialFailure",
                    retryAfter: 1
                )
            }
        )
    }

    func sourceRecord(id: String) -> SourceCloudRecord? {
        return self.sourceRecordsByID[id]
    }

    func favoriteItemRecord(id: String) -> FavoriteItemCloudRecord? {
        return self.favoriteItemRecordsByID.values.first { $0.payload.itemID == id }
    }

    func favoriteItemRecord(sourceID: String, itemID: String) -> FavoriteItemCloudRecord? {
        return self.favoriteItemRecordsByID[
            FavoriteItemIdentity(sourceID: sourceID, itemID: itemID)
        ]
    }

    func events() -> [String] {
        self.eventLock.lock()
        defer { self.eventLock.unlock() }
        return self.recordedEvents
    }

    private func recordEvent(_ event: String) {
        self.eventLock.lock()
        self.recordedEvents.append(event)
        self.eventLock.unlock()
    }

    private static func version(from token: Data?) -> Int {
        guard let token: Data,
              let string: String = String(data: token, encoding: .utf8),
              let version: Int = Int(string) else {
            return 0
        }

        return version
    }

    private static func tokenData(for version: Int) -> Data {
        return Data(String(version).utf8)
    }
}

enum MockCloudRecordStoreError: Error, Equatable {
    case fetchFailed
    case saveFailed
}
