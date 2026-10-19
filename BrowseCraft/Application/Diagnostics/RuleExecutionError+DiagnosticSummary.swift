import BrowseCraftDomain
import BrowseCraftLog

// 中文注释：规则错误的脱敏摘要（docs/design/Problem-Report-Design.md 第七节）。此前日志与 Crashlytics 里只有类型名和
// domain:code，看不出是站点拒绝、选择器空还是解析失败。摘要只写 case 名、状态码、阶段、ruleID 与 operation——
// 不写网址、选择器原文与网页片段（`errorDescription` 内嵌完整网址，不得外泄，`BCA-OBS-008`）。

extension RuleExecutionError: @retroactive DiagnosticSummaryProviding {
    public var diagnosticSummary: String {
        var parts: [String] = ["case=\(self.caseName)"]
        switch self {
        case .httpStatus(_, let statusCode):
            parts.append("status=\(statusCode)")
        case .accessRequired(let stage, _, _),
             .ruleConfiguration(let stage, _, _),
             .responseContract(let stage, _, _),
             .apiResponseContract(let stage, _, _),
             .sourceAPI(let stage, _, _),
             .protectedResource(let stage, _, _):
            parts.append("stage=\(stage.rawValue)")
        case .selectorEmpty(let stage, _, _, let ruleID):
            parts.append("stage=\(stage.rawValue)")
            parts.append("rule=\(ruleID ?? "nil")")
        case .parserDiagnostics(let stage, _, let ruleID, _, let operation, _, _, _):
            parts.append("stage=\(stage.rawValue)")
            parts.append("rule=\(ruleID ?? "nil")")
            parts.append("operation=\(operation)")
        case .network, .antiBot, .unknown:
            break
        }
        return parts.joined(separator: " ")
    }
}
