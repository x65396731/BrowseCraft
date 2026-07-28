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
