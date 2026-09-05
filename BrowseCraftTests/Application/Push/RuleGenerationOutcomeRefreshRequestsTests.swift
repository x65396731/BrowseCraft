import Foundation
import Testing
@testable import BrowseCraft

struct RuleGenerationOutcomeRefreshRequestsTests {
    @Test func requestsBeforeSubscriptionCollapseIntoOne() async {
        let requests: RuleGenerationOutcomeRefreshRequests = RuleGenerationOutcomeRefreshRequests()
        requests.request()
        requests.request()
        requests.request()

        var iterator: AsyncStream<Void>.Iterator = requests.requests.makeAsyncIterator()
        let first: Void? = await iterator.next()

        #expect(first != nil)
        // 中文注释：bufferingNewest(1) 只留最后一条；再要一条必须等新的 request()。
        requests.request()
        let second: Void? = await iterator.next()
        #expect(second != nil)
    }

    @Test func onlyPayloadsWithAJobIDCountAsRuleGenerationOutcomes() {
        #expect(RuleGenerationPushPayload.isRuleGenerationOutcome(["jobId": "5C4F1D3E"]))
        #expect(RuleGenerationPushPayload.isRuleGenerationOutcome(["jobId": ""]) == false)
        #expect(RuleGenerationPushPayload.isRuleGenerationOutcome(["ck": ["ce": 2]]) == false)
        #expect(RuleGenerationPushPayload.isRuleGenerationOutcome([:]) == false)
    }
}
