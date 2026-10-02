import BrowseCraftDomain
import Foundation

struct HistoryPersistenceSnapshot: Sendable {
    let entries: [ReadingHistoryEntry]
    let sources: [Source]
}

struct ReadingHistoryEntriesTransfer: Sendable {
    let values: [ReadingHistoryEntry]
}

actor HistoryPersistenceCoordinator {
    private let loadReadingHistoryEntriesUseCase: LoadReadingHistoryEntriesUseCase
    private let deleteReadingHistoryEntryUseCase: DeleteReadingHistoryEntryUseCase
    private let restoreReadingHistoryUseCase: RestoreReadingHistoryUseCase
    private let reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase

    init(
        loadReadingHistoryEntriesUseCase: LoadReadingHistoryEntriesUseCase,
        deleteReadingHistoryEntryUseCase: DeleteReadingHistoryEntryUseCase,
        restoreReadingHistoryUseCase: RestoreReadingHistoryUseCase,
        reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase
    ) {
        self.loadReadingHistoryEntriesUseCase = loadReadingHistoryEntriesUseCase
        self.deleteReadingHistoryEntryUseCase = deleteReadingHistoryEntryUseCase
        self.restoreReadingHistoryUseCase = restoreReadingHistoryUseCase
        self.reconcileSourceSlotAssignmentsUseCase = reconcileSourceSlotAssignmentsUseCase
    }

    func load(userID: String) throws -> HistoryPersistenceSnapshot {
        return HistoryPersistenceSnapshot(
            entries: try self.loadReadingHistoryEntriesUseCase.execute(userID: userID),
            sources: try self.reconcileSourceSlotAssignmentsUseCase.execute()
        )
    }

    /// 中文注释：按作品删除，返回被删的全部记录，撤销时交回 `restore(_:)`。
    func delete(_ entries: ReadingHistoryEntriesTransfer) throws -> ReadingHistoryRemoval {
        return try self.deleteReadingHistoryEntryUseCase.execute(entries.values)
    }

    func restore(_ removal: ReadingHistoryRemoval) throws {
        try self.restoreReadingHistoryUseCase.execute(removal)
    }
}
