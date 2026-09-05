import Foundation
import Testing
@testable import BrowseCraft

struct RuleGenerationOutcomeRefreshRequestsTests {
    @Test func requestsBeforeSubscriptionCollapseIntoOne() async {
        let requests: RuleGenerationOutcomeRefreshRequests = RuleGenerationOutcomeRefreshRequests()
        requests.request()
        requests.request()
        requests.request()

        var iterator: AsyncStream<RuleGenerationOutcomeRefreshTrigger>.Iterator =
            requests.requests.makeAsyncIterator()
        let first: RuleGenerationOutcomeRefreshTrigger? = await iterator.next()

        #expect(first == .presented)
        // 中文注释：bufferingNewest(1) 只留最后一条；再要一条必须等新的 request()。
        requests.request(.opened)
        let second: RuleGenerationOutcomeRefreshTrigger? = await iterator.next()
        #expect(second == .opened)
    }

    @Test func onlyPayloadsWithAJobIDCountAsRuleGenerationOutcomes() {
        #expect(RuleGenerationPushPayload.isRuleGenerationOutcome(["jobId": "5C4F1D3E"]))
        #expect(RuleGenerationPushPayload.isRuleGenerationOutcome(["jobId": ""]) == false)
        #expect(RuleGenerationPushPayload.isRuleGenerationOutcome(["ck": ["ce": 2]]) == false)
        #expect(RuleGenerationPushPayload.isRuleGenerationOutcome([:]) == false)
    }
}
