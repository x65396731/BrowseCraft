import Foundation

struct SourcesPersistenceSnapshot: @unchecked Sendable {
    let sources: [Source]
    let sourceSlotLimit: Int
}

struct TemporaryResourceHistoryTransfer: @unchecked Sendable {
    let value: TemporaryResourceHistory
}

struct SourcesListSnapshot: @unchecked Sendable {
    let sources: [Source]
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

    func delete(sourceIDs: [String], userID: String) throws -> SourcesPersistenceSnapshot {
        for sourceID: String in sourceIDs {
            try self.deleteSourceUseCase.execute(sourceId: sourceID)
        }
        return SourcesPersistenceSnapshot(
            sources: try self.reconcileSourceSlotAssignmentsUseCase.execute(),
            sourceSlotLimit: try self.loadSourceSlotLimitUseCase.execute(userID: userID)
        )
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
