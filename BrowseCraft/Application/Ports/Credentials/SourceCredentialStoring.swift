import BrowseCraftDomain
import Foundation

/// 中文注释：凭据的写入口只有 App 用（登录页与内存存储），Runtime 只消费 `SourceCredentialProviding`；
/// 2026-10-10 从 BrowseCraftDomain 搬回。
protocol SourceCredentialStoring: SourceCredentialProviding, Sendable {
    func save(_ credential: SourceCredential)
    func removeCredential(sourceID: String)
    func credential(sourceID: String) -> SourceCredential?
}
