import Foundation

// 中文注释：FavoriteItemSyncService 只同步 favorite_items 明细，不直接同步 favorites 聚合 JSON。
final class FavoriteItemSyncService {
    private let localStore: FavoriteItemSyncLocalStore
    private let cloudStore: CloudRecordStore
    private let accountScopeProvider: any ActiveAccountScopeProviding
    private let scope: String
    private let zoneName: String

    init(
        localStore: FavoriteItemSyncLocalStore,
        cloudStore: CloudRecordStore,
        accountScopeProvider: any ActiveAccountScopeProviding = ActiveAccountScopeStore(),
        scope: String = "private",
        zoneName: String = "BrowseCraftSync"
    ) {
        self.localStore = localStore
        self.cloudStore = cloudStore
        self.accountScopeProvider = accountScopeProvider
        self.scope = scope
        self.zoneName = zoneName
    }

    func syncFavoriteItems(limit: Int = 100) async throws -> FavoriteItemSyncResult {
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        var result: FavoriteItemSyncResult = try await self.downloadFavoriteItems(
            accountScope: accountScope
        )
        let uploadResult: FavoriteItemSyncResult = try await self.uploadFavoriteItems(
            accountScope: accountScope,
            limit: limit
        )
        result.add(uploadResult)

        return result
    }

    func downloadFavoriteItems(
        accountScope: CloudAccountScope
    ) async throws -> FavoriteItemSyncResult {
        try self.requireCurrentAccount(accountScope)
        let changeSet: FavoriteItemCloudChangeSet = try await self.fetchCloudChanges(
            accountScope: accountScope
        )
        try self.requireCurrentAccount(accountScope)
        let mergeResult: FavoriteItemMergeResult = try self.mergeCloudChanges(
            changeSet,
            accountScope: accountScope
        )
        return FavoriteItemSyncResult(
            uploadedCount: 0,
            downloadedCount: mergeResult.downloadedCount,
            deletedCount: mergeResult.deletedCount,
            skippedCount: mergeResult.skippedCount,
            failedCount: 0
        )
    }

    func uploadFavoriteItems(
        accountScope: CloudAccountScope,
        limit: Int = 100
    ) async throws -> FavoriteItemSyncResult {
        try self.requireCurrentAccount(accountScope)
        let uploadResult: FavoriteItemUploadResult = try await self.uploadPendingFavoriteItemChanges(
            accountScope: accountScope,
            limit: limit
        )
        try self.requireCurrentAccount(accountScope)
        return FavoriteItemSyncResult(
            uploadedCount: uploadResult.uploadedCount,
            downloadedCount: 0,
            deletedCount: 0,
            skippedCount: uploadResult.skippedCount,
            failedCount: uploadResult.failedCount
        )
    }

    private func fetchCloudChanges(accountScope: CloudAccountScope) async throws -> FavoriteItemCloudChangeSet {
        let token: Data? = try self.localStore.changeToken(
            accountScope: accountScope,
            scope: self.scope,
            zoneName: self.zoneName
        )
        return try await self.cloudStore.fetchChangedFavoriteItemRecords(since: token)
    }

    private func mergeCloudChanges(
        _ changeSet: FavoriteItemCloudChangeSet,
        accountScope: CloudAccountScope
    ) throws -> FavoriteItemMergeResult {
        var result: FavoriteItemMergeResult = FavoriteItemMergeResult()
        var eligiblePayloads: [FavoriteItemCloudPayload] = []

        for payload: FavoriteItemCloudPayload in changeSet.records {
            guard payload.schemaVersion <= FavoriteItemCloudPayload.currentSchemaVersion else {
                result.skippedCount += 1
                continue
            }
            eligiblePayloads.append(payload)
        }

        let keys: [FavoriteItemSyncKey] = eligiblePayloads.map { payload in
            FavoriteItemSyncKey(
                userID: accountScope.rawValue,
                sourceID: payload.sourceID,
                itemID: payload.itemID
            )
        }
        var snapshots: [FavoriteItemSyncKey: FavoriteItemSyncLocalSnapshot] =
            try self.localStore.snapshots(accountScope: accountScope, for: keys)
        var acceptedPayloads: [FavoriteItemCloudPayload] = []
        var requeuedLocalChanges: [FavoriteItemSyncLocalChange] = []

        for payload: FavoriteItemCloudPayload in eligiblePayloads {
            let scopedKey: FavoriteItemSyncKey = FavoriteItemSyncKey(
                userID: accountScope.rawValue,
                sourceID: payload.sourceID,
                itemID: payload.itemID
            )
            if let existing: FavoriteItemSyncLocalSnapshot = snapshots[scopedKey] {
                if Self.remoteChangeWins(
                    remoteChangedAt: payload.lastChangedAt,
                    remoteIsDeleted: payload.isDeleted,
                    localChangedAt: existing.lastChangedAt,
                    localIsDeleted: existing.isDeleted
                ) {
                    acceptedPayloads.append(payload)
                    snapshots[scopedKey] = FavoriteItemSyncLocalSnapshot(
                        key: scopedKey,
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
                            sourceID: existing.key.sourceID,
                            itemID: scopedKey.itemID,
                            operation: existing.isDeleted ? .delete : .upsert,
                            updatedAt: existing.lastChangedAt
                        )
                    )
                    result.skippedCount += 1
                }
            } else {
                acceptedPayloads.append(payload)
                snapshots[scopedKey] = FavoriteItemSyncLocalSnapshot(
                    key: scopedKey,
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
            accountScope: accountScope,
            scope: self.scope,
            zoneName: self.zoneName
        )
        return result
    }

    private func uploadPendingFavoriteItemChanges(
        accountScope: CloudAccountScope,
        limit: Int
    ) async throws -> FavoriteItemUploadResult {
        // 中文注释：limit 是单批上限；失败项保留到下一轮，不在本轮队列快照中重试。
        guard limit > 0 else {
            return FavoriteItemUploadResult(uploadedCount: 0, skippedCount: 0, failedCount: 0)
        }

        let pending: [FavoriteItemSyncPendingUpload] = try self.localStore.pendingUploads(
            accountScope: accountScope
        )
        pending.forEach { pendingUpload in
            CloudSyncDiagnostics.logPendingUpload(pendingUpload.queueItem)
        }
        let orderedPending: [FavoriteItemSyncPendingUpload] = pending.sorted { lhs, rhs in
            if lhs.queueItem.operation != rhs.queueItem.operation {
                return lhs.queueItem.operation == .delete
            }
            return lhs.queueItem.updatedAt < rhs.queueItem.updatedAt
        }
        var aggregate: FavoriteItemUploadResult = FavoriteItemUploadResult(
            uploadedCount: 0,
            skippedCount: 0,
            failedCount: 0
        )
        var batchStart: Int = 0

        while batchStart < orderedPending.count {
            try self.requireCurrentAccount(accountScope)
            let batchEnd: Int = min(batchStart + limit, orderedPending.count)
            let batch: [FavoriteItemSyncPendingUpload] = Array(
                orderedPending[batchStart..<batchEnd]
            )
            let batchResult: FavoriteItemUploadResult = try await self.uploadFavoriteItemBatch(
                batch
            )
            aggregate.add(batchResult)
            try self.requireCurrentAccount(accountScope)
            batchStart = batchEnd
        }
        return aggregate
    }

    private func uploadFavoriteItemBatch(
        _ pending: [FavoriteItemSyncPendingUpload]
    ) async throws -> FavoriteItemUploadResult {
        let payloads: [FavoriteItemCloudPayload] = pending.compactMap(\.payload)

        guard payloads.isEmpty == false else {
            return FavoriteItemUploadResult(
                uploadedCount: 0,
                skippedCount: pending.count,
                failedCount: 0
            )
        }

        let pendingByEntityID: [String: FavoriteItemSyncPendingUpload] = Dictionary(
            uniqueKeysWithValues: pending.map { ($0.queueItem.entityID, $0) }
        )
        let saveResult: CloudRecordBatchSaveResult
        do {
            saveResult = try await self.cloudStore.saveFavoriteItemRecords(payloads)
        } catch {
            let errorMessage: String = CloudSyncSafeErrorMessage.describe(error)
            let retryAfter: TimeInterval? = (error as? CloudRecordOperationError)?.retryAfter
            try self.localStore.markPendingUploadsFailed(
                payloads.compactMap { payload in
                    pendingByEntityID[payload.identity.syncEntityID]?.queueItem
                }.map { item in
                    SyncQueueFailureUpdate(
                        acknowledgement: SyncQueueAcknowledgement(item: item),
                        errorMessage: errorMessage,
                        retryAfter: retryAfter
                    )
                }
            )
            throw error
        }

        let savedQueueItems: [SyncQueueItem] = saveResult.savedEntityIDs.compactMap { entityID in
            return pendingByEntityID[entityID]?.queueItem
        }
        try self.localStore.removePendingUploads(
            acknowledgements: savedQueueItems.map { SyncQueueAcknowledgement(item: $0) }
        )

        for failure: CloudRecordSaveFailure in saveResult.failures {
            guard let queueItem: SyncQueueItem = pendingByEntityID[failure.entityID]?.queueItem else {
                continue
            }
            try self.localStore.markPendingUploadsFailed([
                SyncQueueFailureUpdate(
                    acknowledgement: SyncQueueAcknowledgement(item: queueItem),
                    errorMessage: failure.description,
                    retryAfter: failure.retryAfter
                )
            ])
        }

        return FavoriteItemUploadResult(
            uploadedCount: savedQueueItems.count,
            skippedCount: pending.count - payloads.count,
            failedCount: saveResult.failures.count
        )
    }

    private func requireCurrentAccount(_ accountScope: CloudAccountScope) throws {
        guard self.accountScopeProvider.currentScope == accountScope else {
            throw CloudSyncSessionError.accountChanged
        }
    }

    /// 中文注释：时间相同时 tombstone 优先，避免离线设备用旧内容复活已删除记录。
    private static func remoteChangeWins(
        remoteChangedAt: Date,
        remoteIsDeleted: Bool,
        localChangedAt: Date,
        localIsDeleted: Bool
    ) -> Bool {
        if remoteChangedAt != localChangedAt {
            return remoteChangedAt > localChangedAt
        }
        return remoteIsDeleted || localIsDeleted == false
    }
}

struct FavoriteItemSyncResult: Hashable, Sendable {
    var uploadedCount: Int
    var downloadedCount: Int
    var deletedCount: Int
    var skippedCount: Int
    var failedCount: Int
}

extension FavoriteItemSyncResult {
    mutating func add(_ other: FavoriteItemSyncResult) {
        self.uploadedCount += other.uploadedCount
        self.downloadedCount += other.downloadedCount
        self.deletedCount += other.deletedCount
        self.skippedCount += other.skippedCount
        self.failedCount += other.failedCount
    }
}

private struct FavoriteItemMergeResult {
    var downloadedCount: Int = 0
    var deletedCount: Int = 0
    var skippedCount: Int = 0
}

private struct FavoriteItemUploadResult {
    var uploadedCount: Int
    var skippedCount: Int
    var failedCount: Int

    mutating func add(_ other: FavoriteItemUploadResult) {
        self.uploadedCount += other.uploadedCount
        self.skippedCount += other.skippedCount
        self.failedCount += other.failedCount
    }
}
