import Foundation

// 中文注释：CloudSyncService 是同步用例入口；当前只实现 Source mock 同步。
protocol CloudSyncService {
    func syncSources(limit: Int) throws -> SourceSyncResult
}

struct SourceSyncResult: Hashable {
    var uploadedCount: Int
    var downloadedCount: Int
    var deletedCount: Int
    var skippedCount: Int
}

final class SourceSyncService: CloudSyncService {
    private let localStore: SourceSyncLocalStore
    private let cloudStore: CloudRecordStore
    private let scope: String
    private let zoneName: String

    init(
        localStore: SourceSyncLocalStore,
        cloudStore: CloudRecordStore,
        scope: String = "private",
        zoneName: String = "BrowseCraftSources"
    ) {
        self.localStore = localStore
        self.cloudStore = cloudStore
        self.scope = scope
        self.zoneName = zoneName
    }

    func syncSources(limit: Int = 100) throws -> SourceSyncResult {
        var result: SourceSyncResult = SourceSyncResult(
            uploadedCount: 0,
            downloadedCount: 0,
            deletedCount: 0,
            skippedCount: 0
        )

        let changeSet: SourceCloudChangeSet = try self.fetchCloudChanges()
        let mergeResult: SourceMergeResult = try self.mergeCloudChanges(changeSet)
        result.downloadedCount += mergeResult.downloadedCount
        result.deletedCount += mergeResult.deletedCount
        result.skippedCount += mergeResult.skippedCount

        let uploadResult: SourceUploadResult = try self.uploadPendingSourceChanges(limit: limit)
        result.uploadedCount += uploadResult.uploadedCount
        result.skippedCount += uploadResult.skippedCount

        return result
    }

    private func fetchCloudChanges() throws -> SourceCloudChangeSet {
        let token: Data? = try self.localStore.changeToken(
            scope: self.scope,
            zoneName: self.zoneName
        )
        return try self.cloudStore.fetchChangedSourceRecords(since: token)
    }

    private func mergeCloudChanges(_ changeSet: SourceCloudChangeSet) throws -> SourceMergeResult {
        var result: SourceMergeResult = SourceMergeResult()
        var eligiblePayloads: [SourceCloudPayload] = []

        for payload: SourceCloudPayload in changeSet.records {
            guard payload.isBuiltIn == false,
                  payload.userID == AppUser.localDefaultID,
                  payload.schemaVersion <= SourceCloudPayload.currentSchemaVersion,
                  payload.isUnsupportedVideoV1 == false else {
                result.skippedCount += 1
                continue
            }
            eligiblePayloads.append(payload)
        }

        var snapshots: [String: SourceSyncLocalSnapshot] = try self.localStore.snapshots(
            for: eligiblePayloads.map(\.sourceID)
        )
        var acceptedPayloads: [SourceCloudPayload] = []
        var requeuedLocalChanges: [SourceSyncLocalChange] = []

        for payload: SourceCloudPayload in eligiblePayloads {
            if let existing: SourceSyncLocalSnapshot = snapshots[payload.sourceID] {
                if payload.lastChangedAt >= existing.lastChangedAt {
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
            scope: self.scope,
            zoneName: self.zoneName
        )
        return result
    }

    private func uploadPendingSourceChanges(limit: Int) throws -> SourceUploadResult {
        guard limit > 0 else {
            return SourceUploadResult(uploadedCount: 0, skippedCount: 0)
        }

        let pending: [SourceSyncPendingUpload] = try self.localStore.pendingUploads()
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
            return SourceUploadResult(uploadedCount: 0, skippedCount: orderedPending.count)
        }

        do {
            try self.cloudStore.saveSourceRecords(payloads)
        } catch {
            try self.localStore.markPendingUploadsFailed(
                ids: orderedPending.map(\.queueItem.id),
                errorMessage: String(describing: error)
            )
            throw error
        }

        try self.localStore.removePendingUploads(ids: orderedPending.map(\.queueItem.id))
        return SourceUploadResult(
            uploadedCount: payloads.count,
            skippedCount: orderedPending.count - payloads.count
        )
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
}
