import Foundation

struct FavoriteItemSyncKey: Hashable {
    let userID: String
    let sourceID: String
    let itemID: String

    var identity: FavoriteItemIdentity {
        return FavoriteItemIdentity(sourceID: self.sourceID, itemID: self.itemID)
    }
}

struct FavoriteItemSyncLocalSnapshot: Hashable {
    let key: FavoriteItemSyncKey
    let lastChangedAt: Date
    let isDeleted: Bool
}

struct FavoriteItemSyncLocalChange: Hashable {
    let sourceID: String
    let itemID: String
    let operation: SyncQueueOperation
    let updatedAt: Date
}

struct FavoriteItemSyncMergePlan: Hashable {
    let acceptedPayloads: [FavoriteItemCloudPayload]
    let requeuedLocalChanges: [FavoriteItemSyncLocalChange]
    let changeToken: Data?
}

struct FavoriteItemSyncPendingUpload: Hashable {
    let queueItem: SyncQueueItem
    let payload: FavoriteItemCloudPayload?
}

/// 中文注释：FavoriteItem 同步用例需要的本地原子操作；聚合重建由 GRDB 实现的提交事务负责。
protocol FavoriteItemSyncLocalStore {
    func changeToken(accountScope: CloudAccountScope, scope: String, zoneName: String) throws -> Data?
    func snapshots(
        accountScope: CloudAccountScope,
        for keys: [FavoriteItemSyncKey]
    ) throws -> [FavoriteItemSyncKey: FavoriteItemSyncLocalSnapshot]
    func commit(
        _ plan: FavoriteItemSyncMergePlan,
        accountScope: CloudAccountScope,
        scope: String,
        zoneName: String
    ) throws
    func pendingUploads(accountScope: CloudAccountScope) throws -> [FavoriteItemSyncPendingUpload]
    func removePendingUploads(acknowledgements: [SyncQueueAcknowledgement]) throws
    func markPendingUploadsFailed(_ updates: [SyncQueueFailureUpdate]) throws
}
