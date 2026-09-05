import Foundation

/// 规则生成推送 → 列表刷新的广播（`BC-PREFLIGHT-058` 的 App 侧）。
///
/// 中文注释：推送到达（前台展示）或被点开时，AppDelegate 只知道「有一条生成结果」，
/// 不知道哪个视图模型在看列表；这里把事件变成 AsyncStream，SourcesViewModel 订阅后
/// 自行刷新目录与个人生成结果。没有订阅者时事件被缓冲（最多保留 1 条，多次合并为一次）。
final class RuleGenerationOutcomeRefreshRequests: Sendable {
    private let continuation: AsyncStream<Void>.Continuation
    let requests: AsyncStream<Void>

    init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.requests = stream
        self.continuation = continuation
    }

    func request() {
        self.continuation.yield(())
    }
}

/// 规则生成推送负载的识别（服务端 `notifier.outcome_payload` 的五个自定义字段）。
enum RuleGenerationPushPayload {
    static let jobIDKey: String = "jobId"
    static let statusKey: String = "status"

    /// 只认带 `jobId` 的负载；CloudKit 静默推送与其它通知不触发列表刷新。
    static func isRuleGenerationOutcome(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let jobID: String = userInfo[Self.jobIDKey] as? String else {
            return false
        }
        return jobID.isEmpty == false
    }
}
