import Foundation
import BrowseCraftCore

typealias RuleCandidateDraftApplier = SourceRuleCandidateDraftApplier

extension SourceRuleCandidateDraftApplier {
    func canApply(candidate: RuleCandidate, stage: RuleDebugStage?) -> Bool {
        self.canApply(candidate: candidate, operation: stage?.sourceRuntimeOperation)
    }

    func apply(candidate: RuleCandidate, stage: RuleDebugStage?, ruleID: String?, rule: inout SiteRule) -> Bool {
        self.apply(candidate: candidate, operation: stage?.sourceRuntimeOperation, ruleID: ruleID, rule: &rule)
    }
}
