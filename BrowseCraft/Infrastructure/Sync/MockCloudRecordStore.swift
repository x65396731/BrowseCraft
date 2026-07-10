import Foundation

// 中文注释：MockCloudRecordStore 模拟 CloudKit 的增量 token、保存失败和服务端版本。
final class MockCloudRecordStore: CloudRecordStore {
    private var sourceRecordsByID: [String: SourceCloudRecord]
    private var currentVersion: Int
    private let now: () -> Date

    var failNextFetch: Bool
    var failNextSave: Bool

    init(
        sourceRecords: [SourceCloudRecord] = [],
        now: @escaping () -> Date = Date.init
    ) {
        self.sourceRecordsByID = Dictionary(
            uniqueKeysWithValues: sourceRecords.map { record in
                return (record.payload.sourceID, record)
            }
        )
        self.currentVersion = sourceRecords.map(\.version).max() ?? 0
        self.now = now
        self.failNextFetch = false
        self.failNextSave = false
    }

    func fetchChangedSourceRecords(since token: Data?) throws -> SourceCloudChangeSet {
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

    func saveSourceRecords(_ records: [SourceCloudPayload]) throws {
        if self.failNextSave {
            self.failNextSave = false
            throw MockCloudRecordStoreError.saveFailed
        }

        for payload in records where payload.isBuiltIn == false {
            self.currentVersion += 1
            self.sourceRecordsByID[payload.sourceID] = SourceCloudRecord(
                payload: payload,
                serverUpdatedAt: self.now(),
                version: self.currentVersion
            )
        }
    }

    func sourceRecord(id: String) -> SourceCloudRecord? {
        return self.sourceRecordsByID[id]
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
