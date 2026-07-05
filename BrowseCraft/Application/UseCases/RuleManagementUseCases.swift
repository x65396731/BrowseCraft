import BrowseCraftCore
import Foundation

// 中文注释：RuleManagementUseCases.swift 承载 P2-1 规则管理的校验、更新和复制用例。

typealias SiteRuleValidationResult = BrowseCraftCore.SiteRuleValidationResult
typealias SiteRuleValidator = BrowseCraftCore.SiteRuleValidator

/// 中文注释：更新用户规则；内置规则由 RulesKit 同步，不能被直接覆盖。
struct UpdateSourceRuleUseCase {
    private let sourceRepository: SourceRepository
    private let ruleValidator: SiteRuleValidator

    init(
        sourceRepository: SourceRepository,
        ruleValidator: SiteRuleValidator = SiteRuleValidator()
    ) {
        self.sourceRepository = sourceRepository
        self.ruleValidator = ruleValidator
    }

    func execute(source: Source, ruleJSON: String, expectedUpdatedAt: Date? = nil) throws -> Source {
        let latestSource: Source = try self.latestSource(matching: source) ?? source

        guard latestSource.isBuiltIn == false else {
            throw RuleManagementError.builtInSourceIsReadOnly
        }

        if let expectedUpdatedAt: Date = expectedUpdatedAt,
           latestSource.updatedAt != expectedUpdatedAt {
            throw RuleManagementError.sourceChanged
        }

        let validationResult: SiteRuleValidationResult = self.ruleValidator.validate(ruleJSON: ruleJSON)
        guard validationResult.canSave, let rule: SiteRule = validationResult.rule else {
            throw RuleManagementError.validationFailed(validationResult)
        }

        var updatedSource: Source = latestSource
        updatedSource.name = rule.name
        updatedSource.baseURL = rule.baseUrl
        updatedSource.rule = rule
        updatedSource.updatedAt = Date()
        try self.sourceRepository.saveSource(updatedSource)
        return updatedSource
    }

    private func latestSource(matching source: Source) throws -> Source? {
        return try self.sourceRepository.fetchSources().first { candidate in
            return candidate.id == source.id
        }
    }
}

/// 中文注释：复制规则为用户规则，常用于基于内置规则创建可编辑副本。
struct DuplicateSourceRuleUseCase {
    private let sourceRepository: SourceRepository

    init(sourceRepository: SourceRepository) {
        self.sourceRepository = sourceRepository
    }

    func execute(source: Source) throws -> Source {
        let now: Date = Date()
        let duplicatedSource: Source = Source(
            id: UUID().uuidString,
            name: "\(source.name) Copy",
            baseURL: source.baseURL,
            type: source.type,
            rule: source.rule,
            enabled: source.enabled,
            createdAt: now,
            updatedAt: now
        )

        try self.sourceRepository.saveSource(duplicatedSource)
        return duplicatedSource
    }
}

enum RuleManagementError: LocalizedError {
    case builtInSourceIsReadOnly
    case validationFailed(SiteRuleValidationResult)
    case sourceChanged

    var errorDescription: String? {
        switch self {
        case .builtInSourceIsReadOnly:
            return "Built-in rules are read-only. Duplicate the rule before editing."
        case .validationFailed(let result):
            return result.errors.first?.message ?? "Rule validation failed."
        case .sourceChanged:
            return "This source changed after the editor was opened. Reopen the editor before saving."
        }
    }
}
