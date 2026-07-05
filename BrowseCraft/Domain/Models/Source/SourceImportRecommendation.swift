import Foundation
import BrowseCraftCore

// 中文注释：SourceImportRecommendation 记录系统对添加来源草稿的推荐；推荐结果以 SourceRuntimeKind 为入口轴。
struct SourceImportRecommendation: Codable, Hashable {
    var optionKind: SourceImportOptionKind?
    var sourceType: SourceType?
    var configurationKind: SourceRuntimeKind
    var confidence: SourceImportRecommendationConfidence
    var reasons: [SourceImportRecommendationReason]
    var warnings: [String]

    init(
        optionKind: SourceImportOptionKind? = nil,
        sourceType: SourceType? = nil,
        configurationKind: SourceRuntimeKind,
        confidence: SourceImportRecommendationConfidence,
        reasons: [SourceImportRecommendationReason] = [],
        warnings: [String] = []
    ) {
        self.optionKind = optionKind
        self.sourceType = sourceType
        self.configurationKind = configurationKind
        self.confidence = confidence
        self.reasons = reasons
        self.warnings = warnings
    }
}

enum SourceImportRecommendationConfidence: String, Codable, CaseIterable, Identifiable, Hashable {
    case low
    case medium
    case high

    var id: String {
        return self.rawValue
    }
}

enum SourceImportRecommendationReason: String, Codable, CaseIterable, Identifiable, Hashable {
    case userSelectedOption
    case urlLooksLikeRSS
    case headerLooksLikeRSS
    case htmlContainsRSSLink
    case htmlContainsVideoElement
    case ruleJSONDetected
    case rulePackageDetected
    case pluginManifestDetected
    case knownRuleTemplate

    var id: String {
        return self.rawValue
    }
}

extension SourceImportRecommendation {
    func applying(to draft: SourceImportDraft) -> SourceImportDraft {
        return SourceImportDraft(
            name: draft.name,
            entryURL: draft.entryURL,
            sourceType: self.sourceType ?? draft.sourceType,
            configurationKind: self.configurationKind,
            ruleJSON: draft.ruleJSON
        )
    }

    var isStrongRecommendation: Bool {
        return self.confidence == .high && self.reasons.isEmpty == false
    }
}
