import BrowseCraftDomain
import Foundation

struct LibraryPersistenceSnapshot: Sendable {
    let sources: [Source]
    let favoriteItemIDs: Set<String>
    let libraryState: UserLibraryState?
}

struct LibraryFavoriteMutation: Sendable {
    let item: ContentItem
    let source: Source?
    let favoritedAt: Date
}

struct UserLibraryStateTransfer: Sendable {
    let value: UserLibraryState
}

/// 将 Library 的同步 Repository 调用隔离到专用 actor，ViewModel 只在 MainActor 应用结果。
actor LibraryPersistenceCoordinator {
    private let syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase
    private let reconcileSourceSlotAssignmentsUseCase:
        ReconcileSourceSlotAssignmentsUseCase
    private let toggleFavoriteUseCase: ToggleFavoriteUseCase
    private let loadUserLibraryStateUseCase: LoadUserLibraryStateUseCase
    private let saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase

    init(
        syncBuiltInSourcesUseCase: SyncBuiltInSourcesUseCase,
        reconcileSourceSlotAssignmentsUseCase: ReconcileSourceSlotAssignmentsUseCase,
        toggleFavoriteUseCase: ToggleFavoriteUseCase,
        loadUserLibraryStateUseCase: LoadUserLibraryStateUseCase,
        saveUserLibraryStateUseCase: SaveUserLibraryStateUseCase
    ) {
        self.syncBuiltInSourcesUseCase = syncBuiltInSourcesUseCase
        self.reconcileSourceSlotAssignmentsUseCase = reconcileSourceSlotAssignmentsUseCase
        self.toggleFavoriteUseCase = toggleFavoriteUseCase
        self.loadUserLibraryStateUseCase = loadUserLibraryStateUseCase
        self.saveUserLibraryStateUseCase = saveUserLibraryStateUseCase
    }

    func load(userID: String, selectedSourceID: String?) throws -> LibraryPersistenceSnapshot {
        try self.syncBuiltInSourcesUseCase.execute()
        return LibraryPersistenceSnapshot(
            sources: try self.reconcileSourceSlotAssignmentsUseCase.execute(),
            favoriteItemIDs: try self.toggleFavoriteUseCase.loadFavoriteItemIDs(
                sourceID: selectedSourceID
            ),
            libraryState: try self.loadUserLibraryStateUseCase.execute(userID: userID)
        )
    }

    func favoriteItemIDs(sourceID: String?) throws -> Set<String> {
        return try self.toggleFavoriteUseCase.loadFavoriteItemIDs(sourceID: sourceID)
    }

    func toggleFavorite(_ mutation: LibraryFavoriteMutation) throws -> Set<String> {
        return try self.toggleFavoriteUseCase.execute(
            item: mutation.item,
            source: mutation.source,
            favoritedAt: mutation.favoritedAt
        )
    }

    func save(_ state: UserLibraryStateTransfer) throws {
        try self.saveUserLibraryStateUseCase.execute(state: state.value)
    }
}
