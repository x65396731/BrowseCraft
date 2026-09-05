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
/// 只在 accepted 时调用（`BC-PREFLIGHT-047`）。
protocol VideoGenerationTaskCreating: Sendable {
    func createVideoTask(
        entryURL: String,
        accessToken: String
    ) async throws -> VideoGenerationTaskCreation
}

/// 任务提交所需的会话凭据来源（`BC-PREFLIGHT-045`）。
protocol PortalAccessTokenProviding: Sendable {
    func validAccessToken() async -> String?
}
