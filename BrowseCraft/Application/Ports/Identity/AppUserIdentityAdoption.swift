import Foundation

/// 中文注释：身份采用只处理本地业务数据归属；StoreKit 交易和权益永远不在此边界迁移。
protocol AppUserIdentityAdoptionStoring: Sendable {
    func summary(for userID: UUID) throws -> AppUserIdentityLocalDataSummary

    func prepareAdoption(
        from localUserID: UUID,
        to cloudUserID: UUID,
        decision: CloudAccountLocalDataDecision
    ) throws -> AppUserIdentityAdoptionResult
}

struct AppUserIdentityLocalDataSummary: Hashable, Sendable {
    var sourceCount: Int
    var favoriteItemCount: Int
    var historyCount: Int
    var temporaryResourceCount: Int
    var hasLibraryState: Bool

    var hasMergeableData: Bool {
        return self.sourceCount > 0 ||
            self.favoriteItemCount > 0 ||
            self.historyCount > 0 ||
            self.temporaryResourceCount > 0 ||
            self.hasLibraryState
    }
}

struct AppUserIdentityAdoptionResult: Hashable, Sendable {
    var copiedSourceCount: Int
    var copiedFavoriteItemCount: Int
    var copiedHistoryCount: Int
    var copiedTemporaryResourceCount: Int
    var copiedLibraryState: Bool
}
