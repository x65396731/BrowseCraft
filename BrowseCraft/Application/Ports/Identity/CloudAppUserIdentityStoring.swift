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
}
