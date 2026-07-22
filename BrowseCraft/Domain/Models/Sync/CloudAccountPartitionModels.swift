import Foundation

enum CloudAccountLocalDataDecision: String, Codable, Hashable, Sendable {
    case mergeLocalData
    case useCloudDataOnly
}

struct CloudAccountPartitionPreparation: Hashable, Sendable {
    var decision: CloudAccountLocalDataDecision
    var preparedAt: Date
    var initialSyncCompletedAt: Date?
}

enum CloudSyncInitialRestoreState: Hashable, Sendable {
    case notRequired
    case waitingForCloud
    case restoring
    case restored
    case failed(message: String)

    var shouldReplaceEmptyState: Bool {
        switch self {
        case .waitingForCloud, .restoring, .failed:
            return true
        case .notRequired, .restored:
            return false
        }
    }
}

struct CloudAccountPartitionSummary: Hashable, Sendable {
    var sourceCount: Int
    var favoriteItemCount: Int

    var hasMergeableData: Bool {
        return self.sourceCount > 0 || self.favoriteItemCount > 0
    }
}

struct CloudAccountPartitionMergeResult: Hashable, Sendable {
    var copiedSourceCount: Int
    var copiedFavoriteItemCount: Int
    var skippedCount: Int
    var wasAlreadyPrepared: Bool
}

enum CloudAccountPartitionError: Error, Equatable {
    case invalidCloudScope
    case alreadyPrepared(existingDecision: CloudAccountLocalDataDecision)
}
