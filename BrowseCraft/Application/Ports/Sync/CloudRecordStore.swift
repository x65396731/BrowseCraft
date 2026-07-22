import Foundation

// 中文注释：CloudRecordStore 以 async API 隔离 CKSyncEngine；不得用 semaphore 包装 CloudKit。
protocol CloudRecordStore: Sendable {
    func fetchChangedSourceRecords(since token: Data?) async throws -> SourceCloudChangeSet
    func saveSourceRecords(_ records: [SourceCloudPayload]) async throws -> CloudRecordBatchSaveResult
    func fetchChangedFavoriteItemRecords(since token: Data?) async throws -> FavoriteItemCloudChangeSet
    func saveFavoriteItemRecords(_ records: [FavoriteItemCloudPayload]) async throws -> CloudRecordBatchSaveResult
    func commitState(for accountScope: CloudAccountScope) async throws
    func cancelOperations() async
}

protocol CloudSyncRetryScheduleProviding: Sendable {
    func earliestRetryDate(for accountScope: CloudAccountScope) throws -> Date?
}

struct EmptyCloudSyncRetryScheduleProvider: CloudSyncRetryScheduleProviding {
    func earliestRetryDate(for accountScope: CloudAccountScope) throws -> Date? {
        _ = accountScope
        return nil
    }
}

struct CloudRecordOperationError: Error, Hashable, Sendable, CustomStringConvertible {
    var code: String
    var retryAfter: TimeInterval?

    var description: String {
        var message: String = "Cloud operation failed code=\(self.code)"
        if let retryAfter: TimeInterval {
            message += " retryAfter=\(retryAfter)"
        }
        return message
    }
}

struct SourceCloudChangeSet: Hashable, Sendable {
    var records: [SourceCloudPayload]
    var changeToken: Data?
}

struct FavoriteItemCloudChangeSet: Hashable, Sendable {
    var records: [FavoriteItemCloudPayload]
    var changeToken: Data?
}

struct CloudRecordBatchSaveResult: Hashable, Sendable {
    var savedEntityIDs: Set<String>
    var failures: [CloudRecordSaveFailure]

    static func saved(_ entityIDs: [String]) -> CloudRecordBatchSaveResult {
        return CloudRecordBatchSaveResult(
            savedEntityIDs: Set(entityIDs),
            failures: []
        )
    }
}

struct CloudRecordSaveFailure: Hashable, Sendable, CustomStringConvertible {
    var entityID: String
    var code: String
    var retryAfter: TimeInterval?

    var description: String {
        var message: String = "Cloud record save failed code=\(self.code)"
        if let retryAfter: TimeInterval = self.retryAfter {
            message += " retryAfter=\(retryAfter)"
        }
        return message
    }
}

extension CloudRecordStore {
    func commitState(for accountScope: CloudAccountScope) async throws {
        _ = accountScope
    }

    func cancelOperations() async {}
}
