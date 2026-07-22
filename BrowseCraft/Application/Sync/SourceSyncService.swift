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
        guard limit > 0 else {
            return SourceUploadResult(uploadedCount: 0, skippedCount: 0, failedCount: 0)
        }

        let pending: [SourceSyncPendingUpload] = try self.localStore.pendingUploads(
            accountScope: accountScope
        )
        let orderedPending: [SourceSyncPendingUpload] = Array(pending.sorted { lhs, rhs in
            if lhs.queueItem.operation != rhs.queueItem.operation {
                return lhs.queueItem.operation == .delete
            }
            return lhs.queueItem.updatedAt < rhs.queueItem.updatedAt
        }.prefix(limit))
        let payloads: [SourceCloudPayload] = orderedPending.compactMap { pendingUpload in
            guard let payload: SourceCloudPayload = pendingUpload.payload,
                  payload.isBuiltIn == false else {
                return nil
            }
            return payload
        }

        guard payloads.isEmpty == false else {
            return SourceUploadResult(
                uploadedCount: 0,
                skippedCount: orderedPending.count,
                failedCount: 0
            )
        }

        let pendingByEntityID: [String: SourceSyncPendingUpload] = Dictionary(
            uniqueKeysWithValues: orderedPending.map { ($0.queueItem.entityID, $0) }
        )
        let saveResult: CloudRecordBatchSaveResult
        do {
            saveResult = try await self.cloudStore.saveSourceRecords(payloads)
        } catch {
            try self.localStore.markPendingUploadsFailed(
                ids: payloads.compactMap { pendingByEntityID[$0.sourceID]?.queueItem.id },
                errorMessage: CloudSyncSafeErrorMessage.describe(error)
            )
            throw error
        }

        let savedQueueIDs: [String] = saveResult.savedEntityIDs.compactMap { entityID in
            return pendingByEntityID[entityID]?.queueItem.id
        }
        try self.localStore.removePendingUploads(ids: savedQueueIDs)

        for failure: CloudRecordSaveFailure in saveResult.failures {
            guard let queueID: String = pendingByEntityID[failure.entityID]?.queueItem.id else {
                continue
            }
            try self.localStore.markPendingUploadsFailed(
                ids: [queueID],
                errorMessage: failure.description
            )
        }

        return SourceUploadResult(
            uploadedCount: savedQueueIDs.count,
            skippedCount: orderedPending.count - payloads.count,
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
}
