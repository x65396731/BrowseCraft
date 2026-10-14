import Foundation

protocol PortalSessionStoring: Sendable {
    func load() throws -> PortalSessionPersistence?
    func save(_ session: PortalSessionPersistence) throws
    func clear() throws
}

/// 中文注释：Portal Session 失效时同步撤销本地权益快照，交易审计记录不在此边界删除。
protocol PortalEntitlementCacheResetting: Sendable {
    func resetPortalEntitlements(for userID: UUID) throws
}

/// 中文注释：Bearer 接口回 401 时由调用方报告；会话强制刷新一次，按结果决定是否回到未登录
/// （docs/design/Account-Deletion-Design.md 第 7.1 节）。
enum PortalAuthorizationRejectionOutcome: Equatable, Sendable {
    /// 中文注释：刷新成功，可以用新 token 重试一次。
    case refreshed
    /// 中文注释：刷新被服务端拒绝，会话已清，App 回到未登录。
    case signedOut
    /// 中文注释：连不上或会话本来就不在；会话不动。
    case unchanged
}

protocol PortalAuthorizationRejectionHandling: Sendable {
    func handleAuthorizationRejected() async -> PortalAuthorizationRejectionOutcome
}
