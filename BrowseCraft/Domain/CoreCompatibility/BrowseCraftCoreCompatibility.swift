import Foundation
import BrowseCraftCore

// 中文注释：BrowseCraftCoreCompatibility 是 App 侧唯一 Core 兼容入口；真实规则模型、resolved graph、candidate 合同与 draft applier 实现均定义在 BrowseCraftCore。

typealias SiteRule = BrowseCraftCore.SiteRule
typealias SiteRuleContextValue = BrowseCraftCore.SiteRuleContextValue
typealias ListRule = BrowseCraftCore.ListRule
typealias ListTabRule = BrowseCraftCore.ListTabRule
typealias ListContext = BrowseCraftCore.ListContext
typealias TabGroupRule = BrowseCraftCore.TabGroupRule
typealias TabRule = BrowseCraftCore.TabRule
typealias TabLayout = BrowseCraftCore.TabLayout
typealias DetailRule = BrowseCraftCore.DetailRule
typealias ListAPIRule = BrowseCraftCore.ListAPIRule
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
typealias DetailChapterAPIRule = BrowseCraftCore.DetailChapterAPIRule
typealias APIResponsePolicy = BrowseCraftCore.APIResponsePolicy
typealias APIResponsePolicyMode = BrowseCraftCore.APIResponsePolicyMode
typealias APIResponseScalar = BrowseCraftCore.APIResponseScalar
typealias SectionRole = BrowseCraftCore.SectionRole
typealias ItemLayout = BrowseCraftCore.ItemLayout
typealias ChapterRule = BrowseCraftCore.ChapterRule
typealias ChapterSort = BrowseCraftCore.ChapterSort
typealias GalleryRule = BrowseCraftCore.GalleryRule
typealias ReaderImageAPIRule = BrowseCraftCore.ReaderImageAPIRule
typealias GalleryProtectedResourceRule = BrowseCraftCore.GalleryProtectedResourceRule
typealias ReaderProtectedResourceItemSourceRule = BrowseCraftCore.ReaderProtectedResourceItemSourceRule
typealias ProtectedResourceRule = BrowseCraftCore.ProtectedResourceRule
typealias ProtectedResourceType = BrowseCraftCore.ProtectedResourceType
typealias ProtectedResourceRequestRule = BrowseCraftCore.ProtectedResourceRequestRule
typealias ProtectedResourceDecryptRule = BrowseCraftCore.ProtectedResourceDecryptRule
typealias ProtectedResourceAlgorithm = BrowseCraftCore.ProtectedResourceAlgorithm
typealias ProtectedResourceCipherMode = BrowseCraftCore.ProtectedResourceCipherMode
typealias ProtectedResourcePadding = BrowseCraftCore.ProtectedResourcePadding
typealias ProtectedResourceDataEncoding = BrowseCraftCore.ProtectedResourceDataEncoding
typealias ProtectedResourceValueRule = BrowseCraftCore.ProtectedResourceValueRule
typealias ProtectedResourceValueSource = BrowseCraftCore.ProtectedResourceValueSource
typealias ProtectedResourceOutputRule = BrowseCraftCore.ProtectedResourceOutputRule
typealias ProtectedResourceOutputContentType = BrowseCraftCore.ProtectedResourceOutputContentType
typealias ProtectedResourceKeyDerivationRule = BrowseCraftCore.ProtectedResourceKeyDerivationRule
typealias ProtectedResourceContextSecretDerivationRule = BrowseCraftCore.ProtectedResourceContextSecretDerivationRule
typealias ProtectedResourceKeyEnvelopeDecryptRule = BrowseCraftCore.ProtectedResourceKeyEnvelopeDecryptRule
typealias GalleryVariantRule = BrowseCraftCore.GalleryVariantRule
typealias ResourceLinkRule = BrowseCraftCore.ResourceLinkRule
typealias SearchRule = BrowseCraftCore.SearchRule
typealias KeywordEncoding = BrowseCraftCore.KeywordEncoding
typealias PaginationRule = BrowseCraftCore.PaginationRule
typealias RequestConfig = BrowseCraftCore.RequestConfig
typealias RequestConfigResolver = BrowseCraftCore.RequestConfigResolver
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
typealias VideoSiteRule = BrowseCraftCore.VideoSiteRule
typealias VideoPageRule = BrowseCraftCore.VideoPageRule
typealias VideoPageType = BrowseCraftCore.VideoPageType
typealias VideoRuleRefs = BrowseCraftCore.VideoRuleRefs
typealias VideoRuleSets = BrowseCraftCore.VideoRuleSets
typealias VideoRuleDataSourceStrategy = BrowseCraftCore.VideoRuleDataSourceStrategy
typealias VideoListRule = BrowseCraftCore.VideoListRule
typealias VideoListFields = BrowseCraftCore.VideoListFields
typealias VideoDetailRule = BrowseCraftCore.VideoDetailRule
typealias VideoDetailFields = BrowseCraftCore.VideoDetailFields
typealias VideoDetailMetadataFieldRule = BrowseCraftCore.VideoDetailMetadataFieldRule
typealias VideoEpisodeRule = BrowseCraftCore.VideoEpisodeRule
typealias VideoEpisodeGroupDOMRule = BrowseCraftCore.VideoEpisodeGroupDOMRule
typealias VideoEpisodeFields = BrowseCraftCore.VideoEpisodeFields
typealias VideoDOMScalarMatchRule = BrowseCraftCore.VideoDOMScalarMatchRule
typealias VideoEpisodeSort = BrowseCraftCore.VideoEpisodeSort
typealias VideoListAPIRule = BrowseCraftCore.VideoListAPIRule
typealias VideoListAPIFields = BrowseCraftCore.VideoListAPIFields
typealias VideoDetailAPIRule = BrowseCraftCore.VideoDetailAPIRule
typealias VideoDetailAPIFields = BrowseCraftCore.VideoDetailAPIFields
typealias VideoDetailAPIMetadataFieldRule = BrowseCraftCore.VideoDetailAPIMetadataFieldRule
typealias VideoEpisodeAPIRule = BrowseCraftCore.VideoEpisodeAPIRule
typealias VideoEpisodeAPIGroupFields = BrowseCraftCore.VideoEpisodeAPIGroupFields
typealias VideoEpisodeAPIFields = BrowseCraftCore.VideoEpisodeAPIFields
typealias VideoPlaybackRule = BrowseCraftCore.VideoPlaybackRule
typealias VideoDirectMediaRule = BrowseCraftCore.VideoDirectMediaRule
typealias VideoDirectMediaKind = BrowseCraftCore.VideoDirectMediaKind
typealias VideoIframePlaybackRule = BrowseCraftCore.VideoIframePlaybackRule
typealias VideoIframePlaybackStrategy = BrowseCraftCore.VideoIframePlaybackStrategy
typealias VideoPlaybackFallback = BrowseCraftCore.VideoPlaybackFallback
typealias VideoMediaRequestRule = BrowseCraftCore.VideoMediaRequestRule
typealias ResolvedVideoSiteRule = BrowseCraftCore.ResolvedVideoSiteRule
typealias ResolvedVideoListEntry = BrowseCraftCore.ResolvedVideoListEntry
typealias ResolvedVideoDetailEntry = BrowseCraftCore.ResolvedVideoDetailEntry
typealias ResolvedVideoPlaybackEntry = BrowseCraftCore.ResolvedVideoPlaybackEntry
typealias VideoSiteRuleResolutionError = BrowseCraftCore.VideoSiteRuleResolutionError
typealias VideoSiteRuleValidationResult = BrowseCraftCore.VideoSiteRuleValidationResult
typealias VideoSiteRuleValidationIssue = BrowseCraftCore.VideoSiteRuleValidationIssue
typealias VideoSiteRuleValidator = BrowseCraftCore.VideoSiteRuleValidator
typealias VideoSiteRuleCatalogMetadata = BrowseCraftCore.VideoSiteRuleCatalogMetadata
typealias SourceContentKind = BrowseCraftCore.SourceContentKind
typealias SourceRuntimeKind = BrowseCraftCore.SourceRuntimeKind
typealias SourcePlaybackRequestConfig = BrowseCraftCore.SourcePlaybackRequestConfig
typealias SourceVideoPlaybackHandoff = BrowseCraftCore.SourceVideoPlaybackHandoff
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
        case .debug:
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
