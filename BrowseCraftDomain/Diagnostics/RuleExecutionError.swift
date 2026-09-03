import Foundation

// 中文注释：RuleExecutionError.swift 统一规则执行链路的错误分类，避免 UI 只能显示底层错误字符串。

/// 中文注释：规则执行链路可识别的错误类型，用于区分网络、反爬、选择器空结果和规则配置问题。
public enum RuleExecutionError: LocalizedError, Equatable, Sendable {
    case network(url: String, underlyingDescription: String)
    case antiBot(url: String)
    case accessRequired(stage: RuleExecutionStage, sourceID: String, url: String)
    case selectorEmpty(stage: RuleExecutionStage, sourceID: String, url: String, ruleID: String?)
    case ruleConfiguration(stage: RuleExecutionStage, sourceID: String, reason: String)
    case responseContract(stage: RuleExecutionStage, sourceID: String, reason: String)
    case apiResponseContract(stage: RuleExecutionStage, sourceID: String, reason: String)
    case sourceAPI(stage: RuleExecutionStage, sourceID: String, reason: String)
    case protectedResource(stage: RuleExecutionStage, sourceID: String, reason: String)
    case parserDiagnostics(
        stage: RuleExecutionStage,
        sourceID: String,
        ruleID: String?,
        url: String,
        operation: String,
        selector: String?,
        htmlPreview: String,
        underlyingDescription: String
    )
    case unknown(underlyingDescription: String)

    public var errorDescription: String? {
        switch self {
        case .network(let url, let underlyingDescription):
            return "网络请求失败：\(url)\n\(underlyingDescription)"
        case .antiBot(let url):
            return "源站返回了反爬/验证页面：\(url)"
        case .accessRequired(let stage, let sourceID, let url):
            return "此内容需要源站账号访问：stage=\(stage.rawValue) source=\(sourceID) url=\(url)"
        case .selectorEmpty(let stage, let sourceID, let url, let ruleID):
            return "规则没有匹配到内容：stage=\(stage.rawValue) source=\(sourceID) rule=\(ruleID ?? "nil") url=\(url)"
        case .ruleConfiguration(let stage, let sourceID, let reason):
            return "规则配置错误：stage=\(stage.rawValue) source=\(sourceID) reason=\(reason)"
        case .responseContract(let stage, let sourceID, let reason):
            return "源站响应合同不匹配：stage=\(stage.rawValue) source=\(sourceID) reason=\(reason)"
        case .apiResponseContract(let stage, let sourceID, let reason):
            return "源站接口响应合同不匹配：stage=\(stage.rawValue) source=\(sourceID) reason=\(reason)"
        case .sourceAPI(let stage, let sourceID, let reason):
            return "源站接口返回错误：stage=\(stage.rawValue) source=\(sourceID) reason=\(reason)"
        case .protectedResource(let stage, let sourceID, let reason):
            return "受保护资源处理失败：stage=\(stage.rawValue) source=\(sourceID) reason=\(reason)"
        case .parserDiagnostics(
            let stage,
            let sourceID,
            let ruleID,
            let url,
            let operation,
            let selector,
            let htmlPreview,
            let underlyingDescription
        ):
            return "规则解析错误：stage=\(stage.rawValue) source=\(sourceID) rule=\(ruleID ?? "nil") operation=\(operation) selector=\(selector ?? "nil") url=\(url) error=\(underlyingDescription) htmlPreview=\(htmlPreview)"
        case .unknown(let underlyingDescription):
            return underlyingDescription
        }
    }
}
