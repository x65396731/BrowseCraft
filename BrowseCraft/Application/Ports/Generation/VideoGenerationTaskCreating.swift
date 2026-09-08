import Foundation

/// 任务客户端的稳定错误分类；由 Infrastructure 适配器从 transport 错误映射而来。
enum VideoGenerationTaskClientError: Error, Hashable, Sendable {
    case authRequired
    /// 旧服务端：并发上限。
    case activeJobLimit
    /// 前一个任务未终结（成功或失败）前不接受新任务；带上那条任务的入口 URL。
    case previousJobActive(entryURL: String?)
    /// 每小时提交次数已达上限。
    case rateLimited
    case server(code: String)
    case transport
}

/// 创建规则生成任务的 Application 端口（`BC-PREFLIGHT-048`）。
///
/// 中文注释：`entryURL` 是预检的精确 `submissionString`，实现不得改写；调用方负责
/// 只在 accepted 时调用（`BC-PREFLIGHT-047`）。`sourceKind` 决定服务端走哪条生成链，
/// 两种 kind 共用这一个端口（类型名里的 Video 是历史遗留，在遗留命名清单上）。
/// `refresh` 为 `true` 时服务端跳过查库、强制重新排队。
/// 中文注释：服务端一直支持它，此前是 APIKit 的请求模型没有表达，于是规则生成是
/// **单向的**——同一入口的规则在服务端复用窗口（30 天）内怎么提都直返旧规则，
/// 站点改版、规则生成错了、或引擎修好了都没有办法让它重来。
protocol VideoGenerationTaskCreating: Sendable {
    func createVideoTask(
        sourceKind: RuleGenerationSourceKind,
        entryURL: String,
        refresh: Bool,
        accessToken: String
    ) async throws -> VideoGenerationTaskCreation
}

/// 任务提交所需的会话凭据来源（`BC-PREFLIGHT-045`）。
protocol PortalAccessTokenProviding: Sendable {
    func validAccessToken() async -> String?
}
