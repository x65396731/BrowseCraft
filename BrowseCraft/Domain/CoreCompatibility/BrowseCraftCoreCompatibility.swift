import Foundation
import BrowseCraftCore

// 中文注释：BrowseCraftCoreCompatibility 是 App 侧唯一 Core 兼容入口；真实规则模型、resolved graph、candidate 合同与 draft applier 实现均定义在 BrowseCraftCore。

typealias SiteRule = BrowseCraftCore.SiteRule
typealias ListRule = BrowseCraftCore.ListRule
typealias ListTabRule = BrowseCraftCore.ListTabRule
typealias ListContext = BrowseCraftCore.ListContext
typealias TabGroupRule = BrowseCraftCore.TabGroupRule
typealias TabRule = BrowseCraftCore.TabRule
typealias TabLayout = BrowseCraftCore.TabLayout
typealias DetailRule = BrowseCraftCore.DetailRule
typealias ExtractRule = BrowseCraftCore.ExtractRule
typealias SelectorKind = BrowseCraftCore.SelectorKind
typealias ExtractFunction = BrowseCraftCore.ExtractFunction
typealias SectionRule = BrowseCraftCore.SectionRule
typealias SiteConfig = BrowseCraftCore.SiteConfig
typealias URLPatterns = BrowseCraftCore.URLPatterns
typealias URLTemplateRule = BrowseCraftCore.URLTemplateRule
typealias URLPlaceholderRule = BrowseCraftCore.URLPlaceholderRule
typealias URLPlaceholderKind = BrowseCraftCore.URLPlaceholderKind
typealias PageRule = BrowseCraftCore.PageRule
typealias PageType = BrowseCraftCore.PageType
typealias DisplayMode = BrowseCraftCore.DisplayMode
typealias RuleRefs = BrowseCraftCore.RuleRefs
typealias RuleSets = BrowseCraftCore.RuleSets
typealias SiteFlag = BrowseCraftCore.SiteFlag
typealias PageFlag = BrowseCraftCore.PageFlag
typealias ListFields = BrowseCraftCore.ListFields
typealias DetailFields = BrowseCraftCore.DetailFields
typealias NestedItemRule = BrowseCraftCore.NestedItemRule
typealias TagRule = BrowseCraftCore.TagRule
typealias CommentRule = BrowseCraftCore.CommentRule
typealias PictureRule = BrowseCraftCore.PictureRule
typealias SectionRole = BrowseCraftCore.SectionRole
typealias ItemLayout = BrowseCraftCore.ItemLayout
typealias ChapterRule = BrowseCraftCore.ChapterRule
typealias ChapterSort = BrowseCraftCore.ChapterSort
typealias GalleryRule = BrowseCraftCore.GalleryRule
typealias GalleryVariantRule = BrowseCraftCore.GalleryVariantRule
typealias ResourceLinkRule = BrowseCraftCore.ResourceLinkRule
typealias SearchRule = BrowseCraftCore.SearchRule
typealias KeywordEncoding = BrowseCraftCore.KeywordEncoding
typealias PaginationRule = BrowseCraftCore.PaginationRule
typealias RequestConfig = BrowseCraftCore.RequestConfig
typealias RequestScope = BrowseCraftCore.RequestScope
typealias RequestMergePolicy = BrowseCraftCore.RequestMergePolicy
typealias ImageRequestConfig = BrowseCraftCore.ImageRequestConfig
typealias HTTPMethod = BrowseCraftCore.HTTPMethod
typealias RequestBody = BrowseCraftCore.RequestBody
typealias CookiePolicy = BrowseCraftCore.CookiePolicy
typealias CookiePriority = BrowseCraftCore.CookiePriority
typealias CookieScope = BrowseCraftCore.CookieScope
typealias Charset = BrowseCraftCore.Charset
typealias VideoRule = BrowseCraftCore.VideoRule
typealias SourceContentKind = BrowseCraftCore.SourceContentKind
typealias SourceRuntimeKind = BrowseCraftCore.SourceRuntimeKind
typealias SourcePlaybackRequestConfig = BrowseCraftCore.SourcePlaybackRequestConfig
typealias SourceVideoMediaKind = BrowseCraftCore.SourceVideoMediaKind
typealias SourceVideoPlaybackReference = BrowseCraftCore.SourceVideoPlaybackReference
typealias SourceVideoPlaybackStatus = BrowseCraftCore.SourceVideoPlaybackStatus
typealias SiteRuleValidationResult = BrowseCraftCore.SiteRuleValidationResult
typealias SiteRuleValidator = BrowseCraftCore.SiteRuleValidator
typealias BrowseCraftRulePackage = BrowseCraftCore.BrowseCraftRulePackage
typealias RulePackageMetadata = BrowseCraftCore.BrowseCraftRulePackageMetadata
typealias RulePackageCoder = BrowseCraftCore.RulePackageCoder
typealias RulePackageError = BrowseCraftCore.RulePackageError

extension BrowseCraftCore.SiteRule {
    /// 中文注释：AddRuleSourceView 展示给用户参考的网站规则 JSON 示例。
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

    /// Built-in production rules live in the private BrowseCraftRulesKit package.
    /// Keep this public example generic so the app shell can be published safely.
}

// MARK: - Resolved Rule Compatibility

typealias ResolvedSiteRule = BrowseCraftCore.ResolvedSiteRule
typealias ResolvedDetailEntry = BrowseCraftCore.ResolvedDetailEntry
typealias ResolvedGalleryEntry = BrowseCraftCore.ResolvedGalleryEntry
typealias ResolvedDetailContext = BrowseCraftCore.ResolvedDetailContext
typealias ResolvedReaderContext = BrowseCraftCore.ResolvedReaderContext
typealias RuleResolver = BrowseCraftCore.RuleResolver

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

// MARK: - Rule Candidate Draft Applier Compatibility

typealias RuleCandidateDraftApplier = SourceRuleCandidateDraftApplier

extension SourceRuleCandidateDraftApplier {
    func canApply(candidate: RuleCandidate, stage: RuleDebugStage?) -> Bool {
        self.canApply(candidate: candidate, operation: stage?.sourceRuntimeOperation)
    }

    func apply(candidate: RuleCandidate, stage: RuleDebugStage?, ruleID: String?, rule: inout SiteRule) -> Bool {
        self.apply(candidate: candidate, operation: stage?.sourceRuntimeOperation, ruleID: ruleID, rule: &rule)
    }
}
