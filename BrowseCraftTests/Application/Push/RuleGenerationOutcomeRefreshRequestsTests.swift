import Foundation
import Testing
@testable import BrowseCraft

/// `BC-PREFLIGHT-066` 之后推送只做通知，本文件只剩负载识别（文件名沿用，避免改工程登记）。
struct RuleGenerationOutcomeRefreshRequestsTests {
    @Test func onlyPayloadsWithAJobIDCountAsRuleGenerationOutcomes() {
        #expect(RuleGenerationPushPayload.isRuleGenerationOutcome(["jobId": "5C4F1D3E"]))
        #expect(RuleGenerationPushPayload.isRuleGenerationOutcome(["jobId": ""]) == false)
        #expect(RuleGenerationPushPayload.isRuleGenerationOutcome(["ck": ["ce": 2]]) == false)
        #expect(RuleGenerationPushPayload.isRuleGenerationOutcome([:]) == false)
    }
}
