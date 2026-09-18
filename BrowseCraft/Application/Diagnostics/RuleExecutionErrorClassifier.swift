import BrowseCraftDomain
import Foundation

// 中文注释：本文件原在 Shared/Errors。它的分类分支要认 `CatalogSourceImportError` 与
// `SourceListLoadValidationError` 这两个 Application 层的错误类型，而 Shared 位于 Application 之下、
// 不得反向引用；同时 Application 自己也要用它（`ValidateSourceListLoadUseCase`），所以也不能搬去 Features。
// 归位到 Application 后两个方向同时成立：认识自己的错误类型合规，Features 调用 Application 同样合规。
// （2026-09-18 收敛边界豁免时下沉。）

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

        if let catalogSourceImportError: CatalogSourceImportError = error as? CatalogSourceImportError {
            return .ruleConfiguration(
                stage: .list,
                sourceID: "catalog",
                reason: catalogSourceImportError.localizedDescription
            )
        }

        if let sourceListLoadValidationError: SourceListLoadValidationError = error as? SourceListLoadValidationError {
            switch sourceListLoadValidationError {
            case .emptyList:
                return .selectorEmpty(
                    stage: .list,
                    sourceID: "unknown",
                    url: "unknown",
                    ruleID: nil
                )
            }
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

    /// 中文注释：给用户看的是按类别的本地化短句，`stage=… source=…` 这类诊断细节只进日志
    /// （`log(error:stage:event:)` 仍记完整 `localizedDescription`）。
    static func userMessage(for error: Error) -> String {
        let classifiedError: RuleExecutionError = Self.classified(error)
        func localized(_ key: String) -> String {
            return NSLocalizedString(key, comment: "")
        }
        func withReason(_ key: String, _ reason: String) -> String {
            let trimmed: String = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? localized(key) : "\(localized(key))\n\(trimmed)"
        }
        switch classifiedError {
        case .network(_, let underlyingDescription):
            return withReason("rule_error_network", underlyingDescription)
        case .antiBot:
            return localized("rule_error_anti_bot")
        case .accessRequired:
            return localized("rule_error_access_required")
        case .selectorEmpty:
            return localized("rule_error_selector_empty")
        case .ruleConfiguration(_, _, let reason):
            return withReason("rule_error_rule_configuration", reason)
        case .responseContract(_, _, let reason):
            return withReason("rule_error_response_contract", reason)
        case .apiResponseContract(_, _, let reason):
            return withReason("rule_error_api_response_contract", reason)
        case .sourceAPI(_, _, let reason):
            return withReason("rule_error_source_api", reason)
        case .protectedResource(_, _, let reason):
            return withReason("rule_error_protected_resource", reason)
        case .parserDiagnostics:
            return localized("rule_error_parser")
        case .unknown(let underlyingDescription):
            return withReason("rule_error_unknown", underlyingDescription)
        }
    }

    /// 中文注释：诊断上报的类别判定。分类逻辑只此一处，Shared 的上报入口只接收结果。
    static func diagnosticFailureKind(for error: Error) -> DiagnosticFailureKind {
        switch Self.classified(error) {
        case .network, .antiBot:
            return .network
        case .accessRequired, .selectorEmpty, .ruleConfiguration, .responseContract,
             .apiResponseContract, .sourceAPI, .protectedResource, .parserDiagnostics, .unknown:
            return .parse
        }
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
        case .accessRequired:
            return "accessRequired"
        case .selectorEmpty:
            return "selectorEmpty"
        case .ruleConfiguration:
            return "ruleConfiguration"
        case .responseContract:
            return "responseContract"
        case .apiResponseContract:
            return "apiResponseContract"
        case .sourceAPI:
            return "sourceAPI"
        case .protectedResource:
            return "protectedResource"
        case .parserDiagnostics:
            return "parserDiagnostics"
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
