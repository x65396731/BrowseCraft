import Foundation

/// 中文注释：首次绑定只决定当前 AppUser 数据如何进入选定 CloudAccountScope；scope 不是业务 userID。
protocol CloudAccountPartitioning: Sendable {
    func currentUserSummary() throws -> CloudAccountPartitionSummary
    func preparation(
        for cloudScope: CloudAccountScope
    ) throws -> CloudAccountPartitionPreparation?
    func markInitialSyncCompleted(
        for cloudScope: CloudAccountScope,
        at completedAt: Date
    ) throws
    func prepareCloudScope(
        _ cloudScope: CloudAccountScope,
        decision: CloudAccountLocalDataDecision
    ) throws -> CloudAccountPartitionMergeResult
}

/// 中文注释：本地凭据只记录用户已经手动确认的 CloudAccountScope 与业务 UUID 绑定，不读取 CloudKit Identity。
protocol CloudAppUserAssociationAttestationStoring: Sendable {
    func associatedUserID(for cloudScope: CloudAccountScope) throws -> UUID?
    func attestAssociation(
        cloudScope: CloudAccountScope,
        userID: UUID
    ) throws
}
