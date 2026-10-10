import Foundation

// 中文注释：续看位置同步（`docs/design/History-Resume-Sync-Design.md`）：每部作品一条「看到哪里」，
// 合并规则与来源、收藏一致（`BCA-SYNC-010`）；本机改动不靠写入方登记，而是每轮下载前对比账本找出来。
final class HistoryEntrySyncService: Sendable {
    private let localStore: HistoryEntrySyncLocalStore
    private let cloudStore: CloudRecordStore
    private let accountScopeProvider: any ActiveAccountScopeProviding

    init(
        localStore: HistoryEntrySyncLocalStore,
        cloudStore: CloudRecordStore,
        accountScopeProvider: any ActiveAccountScopeProviding = ActiveAccountScopeStore()
    ) {
        self.localStore = localStore
        self.cloudStore = cloudStore
        self.accountScopeProvider = accountScopeProvider
    }

    func downloadHistoryEntries(
        accountScope: CloudAccountScope
    ) async throws -> HistoryEntrySyncResult {
        try self.requireCurrentAccount(accountScope)
        // 先登记本机改动：合并时本机一侧的时间才是最新的，本机较新的作品也已经在队列里。
        _ = try self.localStore.registerLocalChanges(accountScope: accountScope)
        let changeSet: HistoryEntryCloudChangeSet = try await self.cloudStore.fetchChangedHistoryEntryRecords(since: nil)
        try self.requireCurrentAccount(accountScope)
        let result: HistoryEntrySyncResult = try self.mergeCloudChanges(changeSet, accountScope: accountScope)
        CloudSyncDiagnostics.logDownloadMergeSummary(
            entityType: .historyEntry,
            accountScope: accountScope,
            receivedCount: changeSet.records.count,
            downloadedCount: result.downloadedCount,
            deletedCount: result.deletedCount,
            skippedCount: result.skippedCount
        )
        return result
    }

    func uploadHistoryEntries(
        accountScope: CloudAccountScope,
        limit: Int = 100
    ) async throws -> HistoryEntrySyncResult {
        try self.requireCurrentAccount(accountScope)
        guard limit > 0 else {
            return .zero
        }
        let pending: [HistoryEntrySyncPendingUpload] = try self.localStore.pendingUploads(accountScope: accountScope)
        pending.forEach { pendingUpload in
            CloudSyncDiagnostics.logPendingUpload(pendingUpload.queueItem)
        }
        // 本机既没有历史也没有删除标记的队列项没有东西可传，直接丢弃。
        let orphaned: [HistoryEntrySyncPendingUpload] = pending.filter { $0.payload == nil }
        if orphaned.isEmpty == false {
            try self.localStore.removePendingUploads(
                acknowledgements: orphaned.map { SyncQueueAcknowledgement(item: $0.queueItem) }
            )
        }
        let uploadable: [HistoryEntrySyncPendingUpload] = pending
            .filter { $0.payload != nil }
            .sorted { lhs, rhs in
                if lhs.queueItem.operation != rhs.queueItem.operation {
                    return lhs.queueItem.operation == .delete
                }
                return lhs.queueItem.updatedAt < rhs.queueItem.updatedAt
            }

        var result: HistoryEntrySyncResult = .zero
        result.skippedCount = orphaned.count
        var batchStart: Int = 0
        while batchStart < uploadable.count {
            try self.requireCurrentAccount(accountScope)
            let batchEnd: Int = min(batchStart + limit, uploadable.count)
            let batchResult: HistoryEntrySyncResult = try await self.uploadBatch(
                Array(uploadable[batchStart..<batchEnd])
            )
            result.add(batchResult)
            try self.requireCurrentAccount(accountScope)
            batchStart = batchEnd
        }
        return result
    }

    private func mergeCloudChanges(
        _ changeSet: HistoryEntryCloudChangeSet,
        accountScope: CloudAccountScope
    ) throws -> HistoryEntrySyncResult {
        var result: HistoryEntrySyncResult = .zero
        // 中文注释：类型不认识或版本更新的记录逐条跳过，不拖垮整批。
        let eligible: [HistoryEntryCloudPayload] = changeSet.records.filter { payload in
            return payload.schemaVersion <= HistoryEntryCloudPayload.currentSchemaVersion &&
                HistoryEntryKind(rawValue: payload.kind) != nil
        }
        result.skippedCount += changeSet.records.count - eligible.count

        let availableSourceIDs: Set<String> = try self.localStore.availableSourceIDs(
            among: Set(eligible.map(\.sourceID))
        )
        var snapshots: [HistoryEntryIdentity: HistoryEntrySyncLocalSnapshot] = try self.localStore.snapshots(
            for: eligible.map(\.identity)
        )
        var acceptedPayloads: [HistoryEntryCloudPayload] = []
        var requeuedIdentities: [HistoryEntryIdentity] = []

        for payload: HistoryEntryCloudPayload in eligible {
            let identity: HistoryEntryIdentity = payload.identity
            // 来源不在本机的续看记录用不了：不写入，云端记录保持不动。删除标记照常应用。
            if payload.isDeleted == false, availableSourceIDs.contains(payload.sourceID) == false {
                result.skippedCount += 1
                continue
            }
            if let existing: HistoryEntrySyncLocalSnapshot = snapshots[identity],
               Self.remoteChangeWins(
                remoteChangedAt: payload.lastChangedAt,
                remoteIsDeleted: payload.isDeleted,
                localChangedAt: existing.lastChangedAt,
                localIsDeleted: existing.isDeleted
               ) == false {
                requeuedIdentities.append(identity)
                result.skippedCount += 1
                continue
            }
            acceptedPayloads.append(payload)
            snapshots[identity] = HistoryEntrySyncLocalSnapshot(
                identity: identity,
                lastChangedAt: payload.lastChangedAt,
                isDeleted: payload.isDeleted
            )
            if payload.isDeleted {
                result.deletedCount += 1
            } else {
                result.downloadedCount += 1
            }
        }

        try self.localStore.commit(
            HistoryEntrySyncMergePlan(
                acceptedPayloads: acceptedPayloads,
                requeuedIdentities: requeuedIdentities
            ),
            accountScope: accountScope
        )
        return result
    }

    private func uploadBatch(
        _ pending: [HistoryEntrySyncPendingUpload]
    ) async throws -> HistoryEntrySyncResult {
        let payloads: [HistoryEntryCloudPayload] = pending.compactMap(\.payload)
        let pendingByEntityID: [String: HistoryEntrySyncPendingUpload] = Dictionary(
            pending.map { ($0.queueItem.entityID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let saveResult: CloudRecordBatchSaveResult
        do {
            saveResult = try await self.cloudStore.saveHistoryEntryRecords(payloads)
        } catch {
            let errorMessage: String = CloudSyncSafeErrorMessage.describe(error)
            let retryAfter: TimeInterval? = (error as? CloudRecordOperationError)?.retryAfter
            try self.localStore.markPendingUploadsFailed(
                pending.map { pendingUpload in
                    SyncQueueFailureUpdate(
                        acknowledgement: SyncQueueAcknowledgement(item: pendingUpload.queueItem),
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

        var result: HistoryEntrySyncResult = .zero
        result.uploadedCount = savedQueueItems.count
        result.failedCount = saveResult.failures.count
        return result
    }

    private func requireCurrentAccount(_ accountScope: CloudAccountScope) throws {
        guard self.accountScopeProvider.currentScope == accountScope else {
            throw CloudSyncSessionError.accountChanged
        }
    }

    /// 中文注释：时间相同时删除标记优先，避免离线设备用旧内容复活已删除的历史。
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

struct HistoryEntrySyncResult: Hashable, Sendable {
    var uploadedCount: Int
    var downloadedCount: Int
    var deletedCount: Int
    var skippedCount: Int
    var failedCount: Int

    static let zero: HistoryEntrySyncResult = HistoryEntrySyncResult(
        uploadedCount: 0,
        downloadedCount: 0,
        deletedCount: 0,
        skippedCount: 0,
        failedCount: 0
    )

    mutating func add(_ other: HistoryEntrySyncResult) {
        self.uploadedCount += other.uploadedCount
        self.downloadedCount += other.downloadedCount
        self.deletedCount += other.deletedCount
        self.skippedCount += other.skippedCount
        self.failedCount += other.failedCount
    }
}
