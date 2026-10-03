import Foundation

struct HistoryEntrySyncLocalSnapshot: Hashable {
    let identity: HistoryEntryIdentity
    let lastChangedAt: Date
    let isDeleted: Bool
}

struct HistoryEntrySyncMergePlan: Hashable {
    let acceptedPayloads: [HistoryEntryCloudPayload]
    /// 中文注释：本机较新而没采用云端的作品，重新登记上传。
    let requeuedIdentities: [HistoryEntryIdentity]
}

struct HistoryEntrySyncPendingUpload: Hashable {
    let queueItem: SyncQueueItem
    /// 中文注释：nil 表示这部作品在本机既没有历史也没有删除标记，队列项可以直接丢弃。
    let payload: HistoryEntryCloudPayload?
}

/// 中文注释：续看位置同步需要的本机原子操作（`docs/design/History-Resume-Sync-Design.md` 第四节）。
/// 三张历史表的写入方不登记同步；由 `registerLocalChanges` 在每轮同步时对比账本找出改动。
protocol HistoryEntrySyncLocalStore: Sendable {
    /// 对比历史表与账本，把新增、改动、删除、恢复的作品登记进待上传队列；返回登记了多少部。
    func registerLocalChanges(accountScope: CloudAccountScope) throws -> Int
    func snapshots(
        for identities: [HistoryEntryIdentity]
    ) throws -> [HistoryEntryIdentity: HistoryEntrySyncLocalSnapshot]
    /// 本机现有（未删除或内置）的来源；续看记录指向的来源不在其中时不写入。
    func availableSourceIDs(among sourceIDs: Set<String>) throws -> Set<String>
    func commit(_ plan: HistoryEntrySyncMergePlan, accountScope: CloudAccountScope) throws
    func pendingUploads(accountScope: CloudAccountScope) throws -> [HistoryEntrySyncPendingUpload]
    func removePendingUploads(acknowledgements: [SyncQueueAcknowledgement]) throws
    func markPendingUploadsFailed(_ updates: [SyncQueueFailureUpdate]) throws
    /// 云同步页显示的条数：本机有历史、且来源还在的作品数。
    func syncedWorkCount() throws -> Int
}
