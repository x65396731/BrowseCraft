import Foundation

/// v3：只有输入页一次采集；保留全局 deadline 与请求超时（`BC-PREFLIGHT` §7.4）。
/// 单页超时 25 秒与引擎直接请求取页对齐（fwq `APP-MEMO-044`）：原 12 秒让引擎能生成、要 16～26 秒才响应的慢站卡在检查这一步。
struct VideoGenerationInputSamplingPolicy: Hashable, Sendable {
    let globalDeadlineSeconds: TimeInterval
    let requestTimeoutSeconds: TimeInterval

    init(
        globalDeadlineSeconds: TimeInterval = 30,
        requestTimeoutSeconds: TimeInterval = 25
    ) {
        self.globalDeadlineSeconds = globalDeadlineSeconds
        self.requestTimeoutSeconds = requestTimeoutSeconds
    }
}
