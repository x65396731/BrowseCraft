import Foundation

/// 规则生成推送 → 列表刷新的广播（`BC-PREFLIGHT-058` 的 App 侧）。
///
/// 中文注释：推送到达（前台展示）或被点开时，AppDelegate 只知道「有一条生成结果」，
/// 不知道哪个视图模型在看列表；这里把事件变成 AsyncStream，SourcesViewModel 订阅后
/// 自行刷新目录与个人生成结果。没有订阅者时事件被缓冲（最多保留 1 条，多次合并为一次）。
final class RuleGenerationOutcomeRefreshRequests: Sendable {
    private let continuation: AsyncStream<RuleGenerationOutcomeRefreshTrigger>.Continuation
    let requests: AsyncStream<RuleGenerationOutcomeRefreshTrigger>

    init() {
        let (stream, continuation) = AsyncStream<RuleGenerationOutcomeRefreshTrigger>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.requests = stream
        self.continuation = continuation
    }

    func request(_ trigger: RuleGenerationOutcomeRefreshTrigger = .presented) {
        self.continuation.yield(trigger)
    }
}

/// 中文注释：前台到达只静默刷新数据；用户**点开**推送则要把人带到结果面前
/// （切到 Sources 标签并打开「规则目录」），否则刷新了也看不见（09-05 真机反馈）。
enum RuleGenerationOutcomeRefreshTrigger: String, Sendable {
    case presented
    case opened
}

/// 规则生成推送负载的识别（服务端 `notifier.outcome_payload` 的五个自定义字段）。
enum RuleGenerationPushPayload {
    static let jobIDKey: String = "jobId"
    static let statusKey: String = "status"
    /// 设计书 30.6：终态推送带余额，App 收到即更新本地缓存。
    static let coinBalanceKey: String = "coinBalance"
    static let coinRevisionKey: String = "coinRevision"

    /// 只认带 `jobId` 的负载；CloudKit 静默推送与其它通知不触发列表刷新。
    static func isRuleGenerationOutcome(_ userInfo: [AnyHashable: Any]) -> Bool {
        return Self.outcome(from: userInfo) != nil
    }

    /// 中文注释：在系统回调所在的 nonisolated 上下文里把 `[AnyHashable: Any]` 解成 Sendable 值，
    /// 再切主线程；`userInfo` 本身不可跨隔离域传递。非生成结果负载返回 nil。
    static func outcome(from userInfo: [AnyHashable: Any]) -> RuleGenerationPushOutcome? {
        guard let jobID: String = userInfo[Self.jobIDKey] as? String, jobID.isEmpty == false else {
            return nil
        }
        return RuleGenerationPushOutcome(
            jobID: jobID,
            status: userInfo[Self.statusKey] as? String,
            coinBalance: Self.integer(userInfo[Self.coinBalanceKey]),
            coinRevision: Self.integer(userInfo[Self.coinRevisionKey])
        )
    }

    /// 中文注释：APNs 负载里的数字经 JSON 解成 NSNumber；缺失或 null 都算没有。
    private static func integer(_ value: Any?) -> Int? {
        if let number: NSNumber = value as? NSNumber {
            return number.intValue
        }
        if let text: String = value as? String {
            return Int(text)
        }
        return nil
    }
}

/// 中文注释：推送负载里 App 侧真正用到的字段；解出来后即可安全跨隔离域。
struct RuleGenerationPushOutcome: Sendable, Equatable {
    let jobID: String
    let status: String?
    var coinBalance: Int? = nil
    var coinRevision: Int? = nil
}
