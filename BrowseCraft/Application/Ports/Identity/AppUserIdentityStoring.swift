import Foundation

/// 中文注释：稳定业务身份只保存在受保护存储中；缺少身份与存储失败必须明确区分。
protocol AppUserIdentityStoring: Sendable {
    func loadUserID() throws -> UUID?
    func saveUserID(_ userID: UUID) throws
}

/// 中文注释：单独记录当前业务 UUID 是否已由 Portal 认证，避免退出后把 A 账户数据当成访客数据迁移给 B。
protocol PortalAppUserIdentityOriginStoring: Sendable {
    func containsPortalUserID(_ userID: UUID) throws -> Bool
    func markPortalUserID(_ userID: UUID) throws
}
