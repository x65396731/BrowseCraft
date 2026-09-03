import Foundation
import BrowseCraftCore

// 中文注释：Core 的规则模型就是本应用的领域模型，调用点直接 `import BrowseCraftCore`，
// 不再经由 typealias 隐式注入全局命名空间（否则基于 import 的架构边界检查看不见这层依赖）。
// 这里只保留两类内容：App 侧另起名字的 candidate 合同别名，以及 App 需要的 Core 类型扩展。

typealias RulePackageMetadata = BrowseCraftCore.BrowseCraftRulePackageMetadata

extension BrowseCraftCore.SiteRule {
    /// 中文注释：这里提供给用户参考的是通用网站规则 JSON 示例。
    static let exampleJSON: String = """
    {
      "name": "Example Site",
      "baseUrl": "https://example.com",
      "list": {
        "url": "https://example.com/list/{page}",
        "item": ".card",
        "title": ".title",
        "link": ".title@href",
        "cover": "img@src",
        "type": "comic",
        "latestText": ".badge"
      },
      "detail": {
        "title": "h1",
        "cover": ".cover img@src",
        "chapterContainer": ".chapter-list",
        "chapterItem": ".chapter-list a",
        "chapterTitle": "this",
        "chapterLink": "this@href"
      },
      "gallery": {
        "imageItem": ".reader img",
        "imageUrl": "this@src"
      },
      "video": {
        "videoUrl": "video@src"
      }
    }
    """

    /// Production catalog payloads are provided through BrowseCraftAPIKit.
    /// Keep this public example generic so the app shell can be published safely.
}

// MARK: - Resolved Comic V2 Compatibility

// MARK: - Rule Candidate Compatibility

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

extension RuleAnalysisStage {
    var sourceRuntimeOperation: SourceRuntimeOperation {
        switch self {
        case .list:
            return .list
        case .search:
            return .search
        case .detail:
            return .detail
        case .reader:
            return .reader
        }
    }
}

extension SourceRuntimeOperation {
    var ruleAnalysisStage: RuleAnalysisStage? {
        switch self {
        case .list:
            return .list
        case .search:
            return .search
        case .detail:
            return .detail
        case .reader:
            return .reader
        case .playback, .debug:
            return nil
        }
    }
}

extension BrowseCraftCore.SelectorKind {
    var sourceRuleSelectorKind: SourceRuleSelectorKind {
        switch self {
        case .css:
            return .css
        case .jsonPath:
            return .jsonPath
        case .xpath:
            return .xpath
        case .current:
            return .current
        }
    }
}

extension BrowseCraftCore.ExtractFunction {
    var sourceRuleExtractFunction: SourceRuleExtractFunction {
        switch self {
        case .text:
            return .text
        case .html:
            return .html
        case .attr:
            return .attr
        case .raw:
            return .raw
        case .url:
            return .url
        case .documentURL:
            return .documentURL
        case .decodeBase64:
            return .decodeBase64
        case .removingPercentEncoding:
            return .removingPercentEncoding
        case .addingPercentEncoding:
            return .addingPercentEncoding
        case .replace:
            return .replace
        case .decompressFromBase64:
            return .decompressFromBase64
        case .reversed:
            return .reversed
        case .regexReplacement:
            return .regexReplacement
        }
    }
}

extension SourceRuleCandidateReport {
    init(
        id: String,
        sourceID: String,
        sourceName: String,
        stage: RuleAnalysisStage,
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

    var stage: RuleAnalysisStage {
        self.operation.ruleAnalysisStage ?? .list
    }
}

extension SourceRuleCandidate {
    init(
        id: String,
        field: RuleCandidateField,
        stage: RuleAnalysisStage,
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

    var stage: RuleAnalysisStage {
        self.operation.ruleAnalysisStage ?? .list
    }
}

// MARK: - Rule Candidate Draft Applier Compatibility

typealias RuleCandidateDraftApplier = SourceRuleCandidateDraftApplier

extension SourceRuleCandidateDraftApplier {
    func canApply(candidate: RuleCandidate, stage: RuleAnalysisStage?) -> Bool {
        self.canApply(candidate: candidate, operation: stage?.sourceRuntimeOperation)
    }

    func apply(candidate: RuleCandidate, stage: RuleAnalysisStage?, ruleID: String?, rule: inout SiteRule) -> Bool {
        self.apply(candidate: candidate, operation: stage?.sourceRuntimeOperation, ruleID: ruleID, rule: &rule)
    }
}
