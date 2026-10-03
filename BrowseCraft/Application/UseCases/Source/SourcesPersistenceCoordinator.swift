import BrowseCraftDomain
import Foundation

struct SourcesPersistenceSnapshot: Sendable {
    let sources: [Source]
    let sourceSlotLimit: Int
}

struct TemporaryResourceHistoryTransfer: Sendable {
    let value: TemporaryResourceHistory
}

struct SourcesListSnapshot: Sendable {
    let sources: [Source]
}

/// 删除来源的结果：归置后的列表快照，加上每个被删来源的留底（供撤销；来源不在册时没有对应项）。
struct SourcesDeletionResult: Sendable {
    let snapshot: SourcesPersistenceSnapshot
    let receipts: [SourceDeletionReceipt]
}

/// Sources 页的同步 Repository 操作集中在 actor 内，避免阻塞 SwiftUI MainActor。
actor SourcesPersistenceCoordinator {
    private let syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase
    private let loadSourceSlotLimitUseCase: LoadSourceSlotLimitUseCase
    private let reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase
    private let activateSourceSlotUseCase: ActivateSourceSlotUseCase
    private let deleteSourceUseCase: DeleteSourceUseCase
    private let saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase
    private let saveTemporaryResourceHistoryUseCase: SaveTemporaryResourceHistoryUseCase

    init(
        syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase,
        loadSourceSlotLimitUseCase: LoadSourceSlotLimitUseCase,
        reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase,
        activateSourceSlotUseCase: ActivateSourceSlotUseCase,
        deleteSourceUseCase: DeleteSourceUseCase,
        saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase,
        saveTemporaryResourceHistoryUseCase: SaveTemporaryResourceHistoryUseCase
    ) {
        self.syncBuiltInSourcesUseCase = syncBuiltInSourcesUseCase
        self.loadSourceSlotLimitUseCase = loadSourceSlotLimitUseCase
        self.reconcileSourceSlotAssignmentsUseCase = reconcileSourceSlotAssignmentsUseCase
        self.activateSourceSlotUseCase = activateSourceSlotUseCase
        self.deleteSourceUseCase = deleteSourceUseCase
        self.saveUserLibraryStateUseCase = saveUserLibraryStateUseCase
        self.saveTemporaryResourceHistoryUseCase = saveTemporaryResourceHistoryUseCase
    }

    func load(userID: String) throws -> SourcesPersistenceSnapshot {
        try self.syncBuiltInSourcesUseCase.execute()
        return SourcesPersistenceSnapshot(
            sources: try self.reconcileSourceSlotAssignmentsUseCase.execute(),
            sourceSlotLimit: try self.loadSourceSlotLimitUseCase.execute(userID: userID)
        )
    }

    /// 删除并连带删除历史与收藏；不发同步通知——撤销窗口结束后由 `notifyDeletionChanges()` 补发。
    func delete(sourceIDs: [String], userID: String) throws -> SourcesDeletionResult {
        var receipts: [SourceDeletionReceipt] = []
        for sourceID: String in sourceIDs {
            if let receipt: SourceDeletionReceipt = try self.deleteSourceUseCase.execute(sourceId: sourceID) {
                receipts.append(receipt)
            }
        }
        return SourcesDeletionResult(
            snapshot: SourcesPersistenceSnapshot(
                sources: try self.reconcileSourceSlotAssignmentsUseCase.execute(),
                sourceSlotLimit: try self.loadSourceSlotLimitUseCase.execute(userID: userID)
            ),
            receipts: receipts
        )
    }

    /// 撤销删除：原样写回，再按位置规则归置（恢复的来源更新时间最新，回到在用；补位的来源回到已暂停）。
    func restore(_ receipt: SourceDeletionReceipt, userID: String) throws -> SourcesPersistenceSnapshot {
        try self.deleteSourceUseCase.restore(receipt)
        return SourcesPersistenceSnapshot(
            sources: try self.reconcileSourceSlotAssignmentsUseCase.execute(),
            sourceSlotLimit: try self.loadSourceSlotLimitUseCase.execute(userID: userID)
        )
    }

    /// 撤销窗口结束后把删除告知同步协调器。
    func notifyDeletionChanges() {
        self.deleteSourceUseCase.notifyChanges()
    }

    func activate(sourceID: String, replacingSourceID: String?) throws -> SourcesListSnapshot {
        return SourcesListSnapshot(
            sources: try self.activateSourceSlotUseCase.execute(
                sourceID: sourceID,
                replacingSourceID: replacingSourceID
            )
        )
    }

    func saveLibraryState(_ state: UserLibraryStateTransfer) throws {
        try self.saveUserLibraryStateUseCase.execute(state: state.value)
    }

    func saveTemporaryHistory(_ history: TemporaryResourceHistoryTransfer) throws {
        try self.saveTemporaryResourceHistoryUseCase.execute(history: history.value)
    }
}
