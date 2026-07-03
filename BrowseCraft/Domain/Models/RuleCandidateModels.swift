import Foundation

// RuleCandidateModels defines runtime-only selector recommendations for P2-7.
// These models describe diagnostics and draft hints; they are not persisted as SiteRule JSON.

struct RuleCandidateReport: Identifiable, Hashable {
    var id: String
    var sourceID: String
    var sourceName: String
    var stage: RuleDebugStage
    var pageID: String?
    var ruleID: String?
    var url: String?
    var generatedAt: Date
    var candidates: [RuleCandidate]
    var summary: RuleCandidateSummary
}

struct RuleCandidateSummary: Hashable {
    var candidateCount: Int
    var highConfidenceCount: Int
    var warningCount: Int
    var coveredFields: [RuleCandidateField]
}

struct RuleCandidate: Identifiable, Hashable {
    var id: String
    var field: RuleCandidateField
    var stage: RuleDebugStage
    var selector: String
    var selectorKind: SelectorKind
    var function: ExtractFunction
    var param: String?
    var score: RuleCandidateScore
    var evidence: RuleCandidateEvidence
    var warnings: [RuleCandidateWarning]
    var source: RuleCandidateSource
}

enum RuleCandidateField: String, Hashable {
    case section
    case item
    case title
    case link
    case cover
    case latestText
    case chapterContainer
    case chapterItem
    case chapterTitle
    case chapterLink
    case image
    case nextPage
    case unknown
}

struct RuleCandidateScore: Hashable {
    var value: Double
    var confidence: RuleCandidateConfidence
    var reasons: [String]

    init(value: Double, confidence: RuleCandidateConfidence, reasons: [String]) {
        self.value = min(max(value, 0), 1)
        self.confidence = confidence
        self.reasons = reasons
    }
}

enum RuleCandidateConfidence: String, Hashable {
    case high
    case medium
    case low
    case rejected
}

struct RuleCandidateEvidence: Hashable {
    var candidateCount: Int
    var matchedCount: Int
    var sampleValues: [String]
    var sampleAttributes: [String: [String]]
    var ancestorHints: [String]
}

struct RuleCandidateWarning: Identifiable, Hashable {
    var id: String
    var severity: RuleCandidateWarningSeverity
    var category: RuleCandidateWarningCategory
    var message: String
}

enum RuleCandidateWarningSeverity: String, Hashable {
    case info
    case warning
    case error
}

enum RuleCandidateWarningCategory: String, Hashable {
    case overbroadContainer
    case tooFewMatches
    case missingRequiredField
    case navigationNoise
    case recommendationNoise
    case mixedContent
    case sensitiveSample
    case unknown
}

enum RuleCandidateSource: String, Hashable {
    case repeatedDOMStructure
    case semanticElement
    case attributePattern
    case existingRule
    case debugFailure
    case paginationLink
    case manualSeed
}
