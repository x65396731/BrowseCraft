import Foundation
import BrowseCraftCore

// 中文注释：App 侧 Core rule candidate draft applier 兼容入口；真实实现定义在 BrowseCraftCore。

typealias RuleCandidateDraftApplier = SourceRuleCandidateDraftApplier

extension SourceRuleCandidateDraftApplier {
    func canApply(candidate: RuleCandidate, stage: RuleDebugStage?) -> Bool {
        self.canApply(candidate: candidate, operation: stage?.sourceRuntimeOperation)
    }

    func apply(candidate: RuleCandidate, stage: RuleDebugStage?, ruleID: String?, rule: inout SiteRule) -> Bool {
        self.apply(candidate: candidate, operation: stage?.sourceRuntimeOperation, ruleID: ruleID, rule: &rule)
    }
}
