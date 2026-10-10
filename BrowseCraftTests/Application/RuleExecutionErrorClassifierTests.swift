import BrowseCraftDomain
import Foundation
import Testing
@testable import BrowseCraft

// 中文注释：`BCA-RUNTIME-007`——站点按状态码拒绝要有自己的文案与诊断类别，不能落到「规则解析出错」。
struct RuleExecutionErrorClassifierTests {
    @Test func httpStatusMapsToFourMessageFamilies() {
        #expect(RuleExecutionErrorClassifier.httpStatusMessageKey(403) == "rule_error_http_refused")
        #expect(RuleExecutionErrorClassifier.httpStatusMessageKey(401) == "rule_error_http_refused")
        #expect(RuleExecutionErrorClassifier.httpStatusMessageKey(451) == "rule_error_http_refused")
        #expect(RuleExecutionErrorClassifier.httpStatusMessageKey(400) == "rule_error_http_refused")
        #expect(RuleExecutionErrorClassifier.httpStatusMessageKey(404) == "rule_error_http_not_found")
        #expect(RuleExecutionErrorClassifier.httpStatusMessageKey(410) == "rule_error_http_not_found")
        #expect(RuleExecutionErrorClassifier.httpStatusMessageKey(429) == "rule_error_http_rate_limited")
        #expect(RuleExecutionErrorClassifier.httpStatusMessageKey(500) == "rule_error_http_server")
        #expect(RuleExecutionErrorClassifier.httpStatusMessageKey(503) == "rule_error_http_server")
    }

    @Test func httpStatusMessageCarriesStatusCodeAndIsNotParserMessage() {
        let error: RuleExecutionError = .httpStatus(url: "https://example.test/vodtype/1.html", statusCode: 403)
        let message: String = RuleExecutionErrorClassifier.userMessage(for: error)
        let parserMessage: String = NSLocalizedString("rule_error_parser", comment: "")

        #expect(message.contains("403"))
        #expect(message != parserMessage)
        #expect(message.contains("rule_error_") == false)
    }

    @Test func httpStatusIsDiagnosedAsNetworkNotParse() {
        let error: RuleExecutionError = .httpStatus(url: "https://example.test/", statusCode: 403)

        #expect(RuleExecutionErrorClassifier.classified(error) == error)
        #expect(RuleExecutionErrorClassifier.diagnosticFailureKind(for: error) == .network)
    }
}
