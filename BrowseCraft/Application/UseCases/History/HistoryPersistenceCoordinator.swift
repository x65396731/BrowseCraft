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
    private let reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase

    init(
        loadReadingHistoryEntriesUseCase: LoadReadingHistoryEntriesUseCase,
        deleteReadingHistoryEntryUseCase: DeleteReadingHistoryEntryUseCase,
        reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase
    ) {
        self.loadReadingHistoryEntriesUseCase = loadReadingHistoryEntriesUseCase
        self.deleteReadingHistoryEntryUseCase = deleteReadingHistoryEntryUseCase
        self.reconcileSourceSlotAssignmentsUseCase = reconcileSourceSlotAssignmentsUseCase
    }

    func load(userID: String) throws -> HistoryPersistenceSnapshot {
        return HistoryPersistenceSnapshot(
            entries: try self.loadReadingHistoryEntriesUseCase.execute(userID: userID),
            sources: try self.reconcileSourceSlotAssignmentsUseCase.execute()
        )
    }

    /// 中文注释：按作品删除，返回被删的全部记录（没有撤销，只供记数与日志）。
    func delete(_ entries: ReadingHistoryEntriesTransfer) throws -> ReadingHistoryRemoval {
        return try self.deleteReadingHistoryEntryUseCase.execute(entries.values)
    }
}
