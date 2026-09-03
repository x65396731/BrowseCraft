import Foundation

/// v3：只有输入页一次采集；保留全局 deadline 与请求超时（`BC-PREFLIGHT` §7.4）。
struct VideoGenerationInputSamplingPolicy: Hashable, Sendable {
    let globalDeadlineSeconds: TimeInterval
    let requestTimeoutSeconds: TimeInterval

    init(
        globalDeadlineSeconds: TimeInterval = 30,
        requestTimeoutSeconds: TimeInterval = 12
    ) {
        self.globalDeadlineSeconds = globalDeadlineSeconds
        self.requestTimeoutSeconds = requestTimeoutSeconds
    }
}
