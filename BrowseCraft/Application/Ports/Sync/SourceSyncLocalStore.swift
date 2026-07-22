import Foundation

struct SourceSyncLocalSnapshot: Hashable {
    let sourceID: String
    let lastChangedAt: Date
    let isDeleted: Bool
}

struct SourceSyncLocalChange: Hashable {
    let sourceID: String
    let operation: SyncQueueOperation
    let updatedAt: Date
}

struct SourceSyncMergePlan: Hashable {
    let acceptedPayloads: [SourceCloudPayload]
    let requeuedLocalChanges: [SourceSyncLocalChange]
    let changeToken: Data?
}

struct SourceSyncPendingUpload: Hashable {
    let queueItem: SyncQueueItem
    let payload: SourceCloudPayload?
}

/// 中文注释：Source 同步用例需要的本地原子操作；实现细节和 GRDB Record 留在 Infrastructure。
protocol SourceSyncLocalStore {
    func changeToken(accountScope: CloudAccountScope, scope: String, zoneName: String) throws -> Data?
    func snapshots(
        accountScope: CloudAccountScope,
        for sourceIDs: [String]
    ) throws -> [String: SourceSyncLocalSnapshot]
    func commit(
        _ plan: SourceSyncMergePlan,
        accountScope: CloudAccountScope,
        scope: String,
        zoneName: String
    ) throws
    func pendingUploads(accountScope: CloudAccountScope) throws -> [SourceSyncPendingUpload]
    func removePendingUploads(ids: [String]) throws
    func markPendingUploadsFailed(ids: [String], errorMessage: String) throws
}
