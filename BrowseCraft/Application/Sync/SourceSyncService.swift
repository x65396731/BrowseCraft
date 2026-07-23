import Foundation

// 中文注释：CloudSyncService 是 Source 同步用例入口；下载和上传可由协调器分阶段调用。
protocol CloudSyncService {
    func syncSources(limit: Int) async throws -> SourceSyncResult
}

struct SourceSyncResult: Hashable, Sendable {
    var uploadedCount: Int
    var downloadedCount: Int
    var deletedCount: Int
    var skippedCount: Int
    var failedCount: Int
}

final class SourceSyncService: CloudSyncService {
    private let localStore: SourceSyncLocalStore
    private let cloudStore: CloudRecordStore
    private let accountScopeProvider: any ActiveAccountScopeProviding
    private let scope: String
    private let zoneName: String

    init(
        localStore: SourceSyncLocalStore,
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

    func syncSources(limit: Int = 100) async throws -> SourceSyncResult {
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        var result: SourceSyncResult = try await self.downloadSources(accountScope: accountScope)
        let uploadResult: SourceSyncResult = try await self.uploadSources(
            accountScope: accountScope,
            limit: limit
        )
        result.add(uploadResult)

        return result
    }

    func downloadSources(accountScope: CloudAccountScope) async throws -> SourceSyncResult {
        try self.requireCurrentAccount(accountScope)
        let changeSet: SourceCloudChangeSet = try await self.fetchCloudChanges(accountScope: accountScope)
        try self.requireCurrentAccount(accountScope)
        let mergeResult: SourceMergeResult = try self.mergeCloudChanges(
            changeSet,
            accountScope: accountScope
        )
        CloudSyncDiagnostics.logDownloadMergeSummary(
            entityType: .source,
            accountScope: accountScope,
            receivedCount: changeSet.records.count,
            downloadedCount: mergeResult.downloadedCount,
            deletedCount: mergeResult.deletedCount,
            skippedCount: mergeResult.skippedCount
        )
        return SourceSyncResult(
            uploadedCount: 0,
            downloadedCount: mergeResult.downloadedCount,
            deletedCount: mergeResult.deletedCount,
            skippedCount: mergeResult.skippedCount,
            failedCount: 0
        )
    }

    func uploadSources(
        accountScope: CloudAccountScope,
        limit: Int = 100
    ) async throws -> SourceSyncResult {
        try self.requireCurrentAccount(accountScope)
        let uploadResult: SourceUploadResult = try await self.uploadPendingSourceChanges(
            accountScope: accountScope,
            limit: limit
        )
        try self.requireCurrentAccount(accountScope)
        return SourceSyncResult(
            uploadedCount: uploadResult.uploadedCount,
            downloadedCount: 0,
            deletedCount: 0,
            skippedCount: uploadResult.skippedCount,
            failedCount: uploadResult.failedCount
        )
    }

    private func fetchCloudChanges(accountScope: CloudAccountScope) async throws -> SourceCloudChangeSet {
        let token: Data? = try self.localStore.changeToken(
            accountScope: accountScope,
            scope: self.scope,
            zoneName: self.zoneName
        )
        return try await self.cloudStore.fetchChangedSourceRecords(since: token)
    }

    private func mergeCloudChanges(
        _ changeSet: SourceCloudChangeSet,
        accountScope: CloudAccountScope
    ) throws -> SourceMergeResult {
        var result: SourceMergeResult = SourceMergeResult()
        var eligiblePayloads: [SourceCloudPayload] = []

        for payload: SourceCloudPayload in changeSet.records {
            guard payload.isBuiltIn == false,
                  payload.schemaVersion <= SourceCloudPayload.currentSchemaVersion,
                  payload.isUnsupportedVideoV1 == false else {
                result.skippedCount += 1
                continue
            }
            eligiblePayloads.append(payload)
        }

        var snapshots: [String: SourceSyncLocalSnapshot] = try self.localStore.snapshots(
            accountScope: accountScope,
            for: eligiblePayloads.map(\.sourceID)
        )
        var acceptedPayloads: [SourceCloudPayload] = []
        var requeuedLocalChanges: [SourceSyncLocalChange] = []

        for payload: SourceCloudPayload in eligiblePayloads {
            if let existing: SourceSyncLocalSnapshot = snapshots[payload.sourceID] {
                if Self.remoteChangeWins(
                    remoteChangedAt: payload.lastChangedAt,
                    remoteIsDeleted: payload.isDeleted,
                    localChangedAt: existing.lastChangedAt,
                    localIsDeleted: existing.isDeleted
                ) {
                    acceptedPayloads.append(payload)
                    snapshots[payload.sourceID] = SourceSyncLocalSnapshot(
                        sourceID: payload.sourceID,
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
                        SourceSyncLocalChange(
                            sourceID: existing.sourceID,
                            operation: existing.isDeleted ? .delete : .upsert,
                            updatedAt: existing.lastChangedAt
                        )
                    )
                    result.skippedCount += 1
                }
            } else {
                acceptedPayloads.append(payload)
                snapshots[payload.sourceID] = SourceSyncLocalSnapshot(
                    sourceID: payload.sourceID,
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
            SourceSyncMergePlan(
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

    private func uploadPendingSourceChanges(
        accountScope: CloudAccountScope,
        limit: Int
    ) async throws -> SourceUploadResult {
        // 中文注释：limit 是单批上限；本轮开始时冻结的全部队列项都会依次处理一次。
        guard limit > 0 else {
            return SourceUploadResult(uploadedCount: 0, skippedCount: 0, failedCount: 0)
        }

        let pending: [SourceSyncPendingUpload] = try self.localStore.pendingUploads(
            accountScope: accountScope
        )
        pending.forEach { pendingUpload in
            CloudSyncDiagnostics.logPendingUpload(pendingUpload.queueItem)
        }
        let orderedPending: [SourceSyncPendingUpload] = pending.sorted { lhs, rhs in
            if lhs.queueItem.operation != rhs.queueItem.operation {
                return lhs.queueItem.operation == .delete
            }
            return lhs.queueItem.updatedAt < rhs.queueItem.updatedAt
        }
        var aggregate: SourceUploadResult = SourceUploadResult(
            uploadedCount: 0,
            skippedCount: 0,
            failedCount: 0
        )
        var batchStart: Int = 0

        while batchStart < orderedPending.count {
            try self.requireCurrentAccount(accountScope)
            let batchEnd: Int = min(batchStart + limit, orderedPending.count)
            let batch: [SourceSyncPendingUpload] = Array(orderedPending[batchStart..<batchEnd])
            let batchResult: SourceUploadResult = try await self.uploadSourceBatch(batch)
            aggregate.add(batchResult)
            try self.requireCurrentAccount(accountScope)
            batchStart = batchEnd
        }
        return aggregate
    }

    private func uploadSourceBatch(
        _ pending: [SourceSyncPendingUpload]
    ) async throws -> SourceUploadResult {
        let payloads: [SourceCloudPayload] = pending.compactMap { pendingUpload in
            guard let payload: SourceCloudPayload = pendingUpload.payload,
                  payload.isBuiltIn == false else {
                return nil
            }
            return payload
        }

        guard payloads.isEmpty == false else {
            return SourceUploadResult(
                uploadedCount: 0,
                skippedCount: pending.count,
                failedCount: 0
            )
        }

        let pendingByEntityID: [String: SourceSyncPendingUpload] = Dictionary(
            uniqueKeysWithValues: pending.map { ($0.queueItem.entityID, $0) }
        )
        let saveResult: CloudRecordBatchSaveResult
        do {
            saveResult = try await self.cloudStore.saveSourceRecords(payloads)
        } catch {
            let errorMessage: String = CloudSyncSafeErrorMessage.describe(error)
            let retryAfter: TimeInterval? = (error as? CloudRecordOperationError)?.retryAfter
            try self.localStore.markPendingUploadsFailed(
                payloads.compactMap { payload in
                    pendingByEntityID[payload.sourceID]?.queueItem
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

        return SourceUploadResult(
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

extension SourceSyncResult {
    mutating func add(_ other: SourceSyncResult) {
        self.uploadedCount += other.uploadedCount
        self.downloadedCount += other.downloadedCount
        self.deletedCount += other.deletedCount
        self.skippedCount += other.skippedCount
        self.failedCount += other.failedCount
    }
}

private struct SourceMergeResult {
    var downloadedCount: Int = 0
    var deletedCount: Int = 0
    var skippedCount: Int = 0
}

private struct SourceUploadResult {
    var uploadedCount: Int
    var skippedCount: Int
    var failedCount: Int

    mutating func add(_ other: SourceUploadResult) {
        self.uploadedCount += other.uploadedCount
        self.skippedCount += other.skippedCount
        self.failedCount += other.failedCount
    }
}
