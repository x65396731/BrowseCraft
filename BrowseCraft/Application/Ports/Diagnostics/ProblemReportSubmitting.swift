import Foundation

/// 发往 PortalCore 的一份问题报告（docs/design/Problem-Report-Design.md 第六节）。字段已清洗、截断。
struct ProblemReportPayload: Hashable, Sendable {
    let clientReportID: UUID
    let entry: ProblemReportEntry
    let scope: ProblemReportScope
    let problemType: ProblemReportProblemType
    let note: String?
    let appVersion: String
    let buildNumber: String
    let systemVersion: String
    let deviceModel: String
    let locale: String
    let diagnosticCode: String
    let sessionID: String
    let screen: String
    let sourceID: String
    let sourceKind: String
    let sourceOrigin: String?
    let ruleRevision: String?
    let ruleAppliedAt: String?
    let targetURL: String?
    let targetTitle: String?
    let chapterTitle: String?
    let chapterIndex: Int?
    let categoryKey: String?
    let failure: RuleFailureSnapshot?
    let logs: [String]
}

/// 服务端回的报告编号（形如 R-7KQ2-M9XA）。
struct ProblemReportReceipt: Hashable, Sendable {
    let reportID: String
}

enum ProblemReportSubmissionError: Error, Equatable, Sendable {
    /// 服务端回 429：超出次数上限。
    case rateLimited
    /// 网络或服务端错误。
    case failed
}

/// 发送问题报告的端口，由 Infrastructure 的 APIKit 适配器实现。只在用户点「发送」时调用一次，不重试（`BCA-OBS-018`）。
protocol ProblemReportSubmitting: Sendable {
    func submit(_ payload: ProblemReportPayload, accessToken: String?) async throws -> ProblemReportReceipt
}

/// 读本机日志片段的端口，由组合根接到 `AppLogging`（Shared 不得引用 Application）。
protocol ProblemReportLogProviding: Sendable {
    func recentLogLines(window: TimeInterval, categories: Set<String>, maxLines: Int, maxBytes: Int) -> [String]
}

/// 报告的「环境」与「身份」组，与 Crashlytics 全局键同源，由组合根提供。
struct ProblemReportEnvironment: Hashable, Sendable {
    let appVersion: String
    let buildNumber: String
    let systemVersion: String
    let deviceModel: String
    let locale: String
    let diagnosticCode: String
    let sessionID: String
}
