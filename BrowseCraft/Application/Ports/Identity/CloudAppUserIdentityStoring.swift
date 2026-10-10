import Foundation

/// 中文注释：CloudKit 身份错误在 Application 边界归一化，不向 Feature 暴露 CKError。
enum CloudAppUserIdentityStoreError: Error, Equatable, Sendable {
    case accountUnavailable
    case accessDenied
    case malformedRecord
    case unsupportedSchemaVersion(Int)
    case temporarilyUnavailable
    case operationFailed
}

/// 中文注释：实现必须操作 Private Database default zone 的 AppUserIdentity/default。
protocol CloudAppUserIdentityStoring: Sendable {
    func fetchIdentity() async throws -> CloudAppUserIdentity?

    /// 中文注释：只能“缺失时创建”，不得覆盖既有 userID；并发时返回云端最终权威记录。
    func createIdentityIfAbsent(
        _ proposedIdentity: CloudAppUserIdentity
    ) async throws -> CloudAppUserIdentity

    /// 中文注释：唯一允许覆盖既有 userID 的路径——调用方已判定 `existing` 是本机未登录时写上去的临时 UUID
    /// （`CloudAppUserIdentityAssociationCoordinator.isFormerLocalUser`）。实现仍按 `BCA-SYNC-010`
    /// 显式 `.ifServerRecordUnchanged` 保存；服务端在此期间变过就抛错，由用户重试。
    func replaceIdentity(
        _ identity: CloudAppUserIdentity,
        replacing existing: CloudAppUserIdentity
    ) async throws -> CloudAppUserIdentity
}
