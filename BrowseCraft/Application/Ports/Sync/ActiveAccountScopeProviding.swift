import Foundation

/// 中文注释：同步 Repository 使用同步快照读取活动账户，避免同步 API 依赖 actor 或阻塞等待。
protocol ActiveAccountScopeProviding: Sendable {
    var currentScope: CloudAccountScope { get }
}
