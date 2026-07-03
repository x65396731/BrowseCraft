import Foundation

// 中文注释：RuleExecutionError.swift 统一规则执行链路的错误分类，避免 UI 只能显示底层错误字符串。

/// 中文注释：规则执行链路可识别的错误类型，用于区分网络、反爬、选择器空结果和规则配置问题。
enum RuleExecutionError: LocalizedError {
    case network(url: String, underlyingDescription: String)
    case antiBot(url: String)
    case selectorEmpty(stage: RuleExecutionLogger.Stage, sourceID: String, url: String, ruleID: String?)
    case ruleConfiguration(stage: RuleExecutionLogger.Stage, sourceID: String, reason: String)
    case unknown(underlyingDescription: String)

    var errorDescription: String? {
        switch self {
        case .network(let url, let underlyingDescription):
            return "网络请求失败：\(url)\n\(underlyingDescription)"
        case .antiBot(let url):
            return "源站返回了反爬/验证页面：\(url)"
        case .selectorEmpty(let stage, let sourceID, let url, let ruleID):
            return "规则没有匹配到内容：stage=\(stage.rawValue) source=\(sourceID) rule=\(ruleID ?? "nil") url=\(url)"
        case .ruleConfiguration(let stage, let sourceID, let reason):
            return "规则配置错误：stage=\(stage.rawValue) source=\(sourceID) reason=\(reason)"
        case .unknown(let underlyingDescription):
            return underlyingDescription
        }
    }
}

/// 中文注释：把底层错误归一成 RuleExecutionError，同时为 UI 提供稳定的用户可读文案。
enum RuleExecutionErrorClassifier {
    static func classified(_ error: Error) -> RuleExecutionError {
        if let ruleExecutionError: RuleExecutionError = error as? RuleExecutionError {
            return ruleExecutionError
        }

        if let urlResolvingError: URLResolvingError = error as? URLResolvingError {
            return .ruleConfiguration(
                stage: .list,
                sourceID: "unknown",
                reason: urlResolvingError.localizedDescription
            )
        }

        let nsError: NSError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .network(
                url: Self.urlString(from: nsError),
                underlyingDescription: nsError.localizedDescription
            )
        }

        let description: String = error.localizedDescription
        if description.localizedCaseInsensitiveContains("Unsupported extract")
            || description.localizedCaseInsensitiveContains("Unsupported selector")
            || description.localizedCaseInsensitiveContains("regexReplacement")
            || description.localizedCaseInsensitiveContains("replace requires") {
            return .ruleConfiguration(
                stage: .list,
                sourceID: "unknown",
                reason: description
            )
        }

        return .unknown(underlyingDescription: description)
    }

    static func userMessage(for error: Error) -> String {
        return Self.classified(error).localizedDescription
    }

    /// 中文注释：Debug 日志记录分类结果，UI 仍只展示简短错误文案。
    static func log(error: Error, stage: RuleExecutionLogger.Stage, event: String) {
        let classifiedError: RuleExecutionError = Self.classified(error)
        RuleExecutionLogger.log(
            stage: stage,
            event: event,
            fields: [
                "category": Self.categoryName(classifiedError),
                "message": classifiedError.localizedDescription
            ]
        )
    }

    private static func categoryName(_ error: RuleExecutionError) -> String {
        switch error {
        case .network:
            return "network"
        case .antiBot:
            return "antiBot"
        case .selectorEmpty:
            return "selectorEmpty"
        case .ruleConfiguration:
            return "ruleConfiguration"
        case .unknown:
            return "unknown"
        }
    }

    private static func urlString(from nsError: NSError) -> String {
        if let failingURL: URL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            return failingURL.absoluteString
        }

        if let failingURLString: String = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
            return failingURLString
        }

        return "unknown"
    }
}
