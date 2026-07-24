import Foundation

/// 中文注释：稳定业务身份只保存在受保护存储中；缺少身份与存储失败必须明确区分。
protocol AppUserIdentityStoring: Sendable {
    func loadUserID() throws -> UUID?
    func saveUserID(_ userID: UUID) throws
}
