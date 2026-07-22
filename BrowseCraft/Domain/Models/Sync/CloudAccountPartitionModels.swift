import Foundation

enum CloudAccountLocalDataDecision: Hashable, Sendable {
    case mergeLocalData
    case useCloudDataOnly
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
}
