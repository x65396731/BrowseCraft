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

    func delete(_ entries: ReadingHistoryEntriesTransfer) throws {
        for entry: ReadingHistoryEntry in entries.values {
            try self.deleteReadingHistoryEntryUseCase.execute(entry)
        }
    }
}
