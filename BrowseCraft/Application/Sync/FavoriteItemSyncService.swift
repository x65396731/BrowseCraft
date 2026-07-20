import Foundation

// 中文注释：FavoriteItemSyncService 只同步 favorite_items 明细，不直接同步 favorites 聚合 JSON。
final class FavoriteItemSyncService {
    private let localStore: FavoriteItemSyncLocalStore
    private let cloudStore: CloudRecordStore
    private let scope: String
    private let zoneName: String

    init(
        localStore: FavoriteItemSyncLocalStore,
        cloudStore: CloudRecordStore,
        scope: String = "private",
        zoneName: String = "BrowseCraftFavoriteItems"
    ) {
        self.localStore = localStore
        self.cloudStore = cloudStore
        self.scope = scope
        self.zoneName = zoneName
    }

    func syncFavoriteItems(limit: Int = 100) throws -> FavoriteItemSyncResult {
        var result: FavoriteItemSyncResult = FavoriteItemSyncResult(
            uploadedCount: 0,
            downloadedCount: 0,
            deletedCount: 0,
            skippedCount: 0
        )

        let changeSet: FavoriteItemCloudChangeSet = try self.fetchCloudChanges()
        let mergeResult: FavoriteItemMergeResult = try self.mergeCloudChanges(changeSet)
        result.downloadedCount += mergeResult.downloadedCount
        result.deletedCount += mergeResult.deletedCount
        result.skippedCount += mergeResult.skippedCount

        let uploadResult: FavoriteItemUploadResult = try self.uploadPendingFavoriteItemChanges(limit: limit)
        result.uploadedCount += uploadResult.uploadedCount
        result.skippedCount += uploadResult.skippedCount

        return result
    }

    private func fetchCloudChanges() throws -> FavoriteItemCloudChangeSet {
        let token: Data? = try self.localStore.changeToken(
            scope: self.scope,
            zoneName: self.zoneName
        )
        return try self.cloudStore.fetchChangedFavoriteItemRecords(since: token)
    }

    private func mergeCloudChanges(_ changeSet: FavoriteItemCloudChangeSet) throws -> FavoriteItemMergeResult {
        var result: FavoriteItemMergeResult = FavoriteItemMergeResult()
        var eligiblePayloads: [FavoriteItemCloudPayload] = []

        for payload: FavoriteItemCloudPayload in changeSet.records {
            guard payload.userID == AppUser.localDefaultID,
                  payload.schemaVersion <= FavoriteItemCloudPayload.currentSchemaVersion else {
                result.skippedCount += 1
                continue
            }
            eligiblePayloads.append(payload)
        }

        let keys: [FavoriteItemSyncKey] = eligiblePayloads.map { payload in
            FavoriteItemSyncKey(userID: payload.userID, itemID: payload.itemID)
        }
        var snapshots: [FavoriteItemSyncKey: FavoriteItemSyncLocalSnapshot] =
            try self.localStore.snapshots(for: keys)
        var acceptedPayloads: [FavoriteItemCloudPayload] = []
        var requeuedLocalChanges: [FavoriteItemSyncLocalChange] = []

        for payload: FavoriteItemCloudPayload in eligiblePayloads {
            let key: FavoriteItemSyncKey = FavoriteItemSyncKey(
                userID: payload.userID,
                itemID: payload.itemID
            )
            if let existing: FavoriteItemSyncLocalSnapshot = snapshots[key] {
                if payload.lastChangedAt >= existing.lastChangedAt {
                    acceptedPayloads.append(payload)
                    snapshots[key] = FavoriteItemSyncLocalSnapshot(
                        key: key,
                        lastChangedAt: payload.lastChangedAt,
                        isDeleted: payload.isDeleted
                    )
                    if payload.isDeleted {
                        result.deletedCount += 1
                    } else {
                        result.downloadedCount += 1
                    }
                } else {
                    requeuedLocalChanges.append(
                        FavoriteItemSyncLocalChange(
                            itemID: key.itemID,
                            operation: existing.isDeleted ? .delete : .upsert,
                            updatedAt: existing.lastChangedAt
                        )
                    )
                    result.skippedCount += 1
                }
            } else {
                acceptedPayloads.append(payload)
                snapshots[key] = FavoriteItemSyncLocalSnapshot(
                    key: key,
                    lastChangedAt: payload.lastChangedAt,
                    isDeleted: payload.isDeleted
                )
                if payload.isDeleted {
                    result.deletedCount += 1
                } else {
                    result.downloadedCount += 1
                }
            }
        }

        try self.localStore.commit(
            FavoriteItemSyncMergePlan(
                acceptedPayloads: acceptedPayloads,
                requeuedLocalChanges: requeuedLocalChanges,
                changeToken: changeSet.changeToken
            ),
            scope: self.scope,
            zoneName: self.zoneName
        )
        return result
    }

    private func uploadPendingFavoriteItemChanges(limit: Int) throws -> FavoriteItemUploadResult {
        guard limit > 0 else {
            return FavoriteItemUploadResult(uploadedCount: 0, skippedCount: 0)
        }

        let pending: [FavoriteItemSyncPendingUpload] = try self.localStore.pendingUploads(
            userID: AppUser.localDefaultID
        )
        let orderedPending: [FavoriteItemSyncPendingUpload] = Array(pending.sorted { lhs, rhs in
            if lhs.queueItem.operation != rhs.queueItem.operation {
                return lhs.queueItem.operation == .delete
            }
            return lhs.queueItem.updatedAt < rhs.queueItem.updatedAt
        }.prefix(limit))
        let payloads: [FavoriteItemCloudPayload] = orderedPending.compactMap(\.payload)

        guard payloads.isEmpty == false else {
            return FavoriteItemUploadResult(uploadedCount: 0, skippedCount: orderedPending.count)
        }

        do {
            try self.cloudStore.saveFavoriteItemRecords(payloads)
        } catch {
            try self.localStore.markPendingUploadsFailed(
                ids: orderedPending.map(\.queueItem.id),
                errorMessage: String(describing: error)
            )
            throw error
        }

        try self.localStore.removePendingUploads(ids: orderedPending.map(\.queueItem.id))
        return FavoriteItemUploadResult(
            uploadedCount: payloads.count,
            skippedCount: orderedPending.count - payloads.count
        )
    }
}

struct FavoriteItemSyncResult: Hashable {
    var uploadedCount: Int
    var downloadedCount: Int
    var deletedCount: Int
    var skippedCount: Int
}

private struct FavoriteItemMergeResult {
    var downloadedCount: Int = 0
    var deletedCount: Int = 0
    var skippedCount: Int = 0
}

private struct FavoriteItemUploadResult {
    var uploadedCount: Int
    var skippedCount: Int
}
