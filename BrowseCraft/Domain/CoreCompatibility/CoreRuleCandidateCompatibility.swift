import BrowseCraftCore
import Foundation

// 中文注释：Domain/CoreCompatibility 集中承载 App 侧 Core rule candidate 兼容入口；稳定 candidate 合同定义在 BrowseCraftCore。

typealias RuleCandidateReport = SourceRuleCandidateReport
typealias RuleCandidateSummary = SourceRuleCandidateSummary
typealias RuleCandidate = SourceRuleCandidate
typealias RuleCandidateField = SourceRuleField
typealias RuleCandidateScore = SourceRuleCandidateScore
typealias RuleCandidateConfidence = SourceRuleCandidateConfidence
typealias RuleCandidateEvidence = SourceRuleCandidateEvidence
typealias RuleCandidateWarning = SourceRuleCandidateWarning
typealias RuleCandidateWarningSeverity = SourceRuleCandidateWarningSeverity
typealias RuleCandidateWarningCategory = SourceRuleCandidateWarningCategory
typealias RuleCandidateSource = SourceRuleCandidateSource

extension SourceRuleCandidateReport {
    init(
        id: String,
        sourceID: String,
        sourceName: String,
        stage: RuleDebugStage,
        pageID: String?,
        ruleID: String?,
        url: String?,
        generatedAt: Date,
        candidates: [RuleCandidate],
        summary: RuleCandidateSummary
    ) {
        self.init(
            id: id,
            sourceID: sourceID,
            sourceName: sourceName,
            operation: stage.sourceRuntimeOperation,
            pageID: pageID,
            ruleID: ruleID,
            url: url,
            generatedAt: generatedAt,
            candidates: candidates,
            summary: summary
        )
    }

    var stage: RuleDebugStage {
        self.operation.ruleDebugStage ?? .list
    }
}

extension SourceRuleCandidate {
    init(
        id: String,
        field: RuleCandidateField,
        stage: RuleDebugStage,
        selector: String,
        selectorKind: SelectorKind,
        function: ExtractFunction,
        param: String?,
        score: RuleCandidateScore,
        evidence: RuleCandidateEvidence,
        warnings: [RuleCandidateWarning],
        source: RuleCandidateSource
    ) {
        self.init(
            id: id,
            field: field,
            operation: stage.sourceRuntimeOperation,
            selector: selector,
            selectorKind: selectorKind.sourceRuleSelectorKind,
            function: function.sourceRuleExtractFunction,
            param: param,
            score: score,
            evidence: evidence,
            warnings: warnings,
            source: source
        )
    }

    var stage: RuleDebugStage {
        self.operation.ruleDebugStage ?? .list
    }
}
