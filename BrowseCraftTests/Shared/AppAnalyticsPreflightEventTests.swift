import Foundation
import Testing
import BrowseCraftDomain
@testable import BrowseCraft

/// 预检结果埋点只报类别、原因码与主机名哈希（设计书 30.8「预检结果埋点」）。
struct AppAnalyticsPreflightEventTests {
    @Test func executionErrorsMapToStableCodes() {
        #expect(AppAnalytics.preflightErrorCode(for: VideoGenerationInputURLValidationError.invalidURL) == "invalidInput")
        #expect(AppAnalytics.preflightErrorCode(for: VideoGenerationInputPreflightExecutionIssue.unsafeURL) == "unsafeURL")
        #expect(AppAnalytics.preflightErrorCode(for: VideoGenerationInputPreflightExecutionIssue.unsupportedContent) == "unsupportedContent")
        #expect(AppAnalytics.preflightErrorCode(for: VideoGenerationInputPreflightExecutionIssue.requestFailed) == "requestFailed")
        #expect(AppAnalytics.preflightErrorCode(for: CocoaError(.fileNoSuchFile)) == "unknown")
    }

    @Test func hostHashIgnoresCaseAndNeverCarriesTheURL() {
        let lower: String? = AppAnalytics.hostHash("yhdm.one")
        #expect(lower != nil)
        #expect(lower == AppAnalytics.hostHash("YHDM.one"))
        #expect(lower?.contains("yhdm") == false)
        #expect(lower?.count == 64)
        #expect(AppAnalytics.hostHash(nil) == nil)
        #expect(AppAnalytics.hostHash("") == nil)
    }

    @Test func preflightStatusesAreTheAnalyticsValues() {
        #expect(VideoGenerationInputPreflightStatus.accepted.rawValue == "accepted")
        #expect(VideoGenerationInputPreflightStatus.rejected.rawValue == "rejected")
        #expect(VideoGenerationInputPreflightStatus.inconclusive.rawValue == "inconclusive")
    }
}
