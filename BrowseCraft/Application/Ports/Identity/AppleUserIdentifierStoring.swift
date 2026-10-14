import Foundation

/// 中文注释：本机保存最近一次 Apple 登录的 user 标识，只用于查询凭据状态（删除账号设计第十节）。
/// 它不是业务身份，也不随 iCloud 同步；读不到就跳过凭据检查。
protocol AppleUserIdentifierStoring: Sendable {
    func loadUserIdentifier() throws -> String?
    /// 中文注释：最近一次保存（即最近一次 Apple 授权成功）的时间；旧格式或没存过返回 nil。只用于诊断日志。
    func lastAuthorizedAt() throws -> Date?
    /// 中文注释：这次授权之后，系统是否至少回过一次 authorized（删除账号设计第十节）。
    func hasObservedAuthorized() throws -> Bool
    func markObservedAuthorized() throws
    /// 中文注释：保存新标识即开始新一轮授权，「见过 authorized」随之清零。
    func saveUserIdentifier(_ userIdentifier: String) throws
    func clearUserIdentifier() throws
}

/// 中文注释：Apple 凭据状态归一化；revoked 与 notFound 都按退出登录处理，其余不动。
enum AppleCredentialState: Equatable, Sendable {
    case authorized
    case revoked
    case notFound
    case transferred
    case unknown
}

protocol AppleCredentialStateChecking: Sendable {
    func credentialState(forUserIdentifier userIdentifier: String) async -> AppleCredentialState
    /// 中文注释：系统在用户于设置里停用「通过 Apple 登录」时发出的通知流。
    func revocationNotifications() -> AsyncStream<Void>
}
