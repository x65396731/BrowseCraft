import Foundation

// 中文注释：RuleManagementUseCases.swift 承载 P2-1 规则管理的校验、更新和复制用例。

/// 中文注释：规则校验结果按严重程度区分，UI 可直接展示摘要和明细。
struct RuleValidationResult: Hashable {
    enum Severity: String, Hashable {
        case error
        case warning
    }

    struct Issue: Identifiable, Hashable {
        let id: String
        let severity: Severity
        let message: String
    }

    let rule: SiteRule?
    let issues: [Issue]

    var canSave: Bool {
        return self.rule != nil && self.issues.contains { issue in
            return issue.severity == .error
        } == false
    }

    var errors: [Issue] {
        return self.issues.filter { issue in
            return issue.severity == .error
        }
    }

    var warnings: [Issue] {
        return self.issues.filter { issue in
            return issue.severity == .warning
        }
    }
}

/// 中文注释：RuleValidator 只做结构与引用校验，不执行网络请求或 selector 匹配。
struct RuleValidator {
    private let jsonDecoder: JSONDecoder

    init(jsonDecoder: JSONDecoder = JSONDecoder()) {
        self.jsonDecoder = jsonDecoder
    }

    func validate(ruleJSON: String) -> RuleValidationResult {
        let ruleData: Data = Data(ruleJSON.utf8)

        do {
            let rule: SiteRule = try self.jsonDecoder.decode(SiteRule.self, from: ruleData)
            return self.validate(rule: rule)
        } catch {
            return RuleValidationResult(
                rule: nil,
                issues: [
                    RuleValidationResult.Issue(
                        id: "json-decode",
                        severity: .error,
                        message: "Rule JSON cannot be decoded: \(error.localizedDescription)"
                    )
                ]
            )
        }
    }

    func validate(rule: SiteRule) -> RuleValidationResult {
        var issues: [RuleValidationResult.Issue] = []

        self.appendRequiredFieldIssues(rule: rule, issues: &issues)
        self.appendPageIssues(rule: rule, issues: &issues)
        self.appendRuleSetIssues(rule: rule, issues: &issues)
        self.appendRuleReferenceIssues(rule: rule, issues: &issues)
        self.appendPrimaryFlowIssues(rule: rule, issues: &issues)

        return RuleValidationResult(rule: rule, issues: issues)
    }

    private func appendRequiredFieldIssues(rule: SiteRule, issues: inout [RuleValidationResult.Issue]) {
        if rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                RuleValidationResult.Issue(
                    id: "site-name-empty",
                    severity: .error,
                    message: "Rule name is required."
                )
            )
        }

        if rule.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                RuleValidationResult.Issue(
                    id: "base-url-empty",
                    severity: .error,
                    message: "Base URL is required."
                )
            )
        }

        if rule.pages?.isEmpty == true {
            issues.append(
                RuleValidationResult.Issue(
                    id: "pages-empty",
                    severity: .warning,
                    message: "V2 pages are empty; legacy list/detail/gallery fallback will be used."
                )
            )
        }
    }

    private func appendPageIssues(rule: SiteRule, issues: inout [RuleValidationResult.Issue]) {
        guard let pages: [PageRule] = rule.pages else {
            return
        }

        var seenPageIDs: Set<String> = []

        for page: PageRule in pages {
            let pageID: String = page.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if pageID.isEmpty {
                issues.append(
                    RuleValidationResult.Issue(
                        id: "page-id-empty",
                        severity: .error,
                        message: "Page id is required."
                    )
                )
            } else if seenPageIDs.contains(pageID) {
                issues.append(
                    RuleValidationResult.Issue(
                        id: "page-id-duplicate-\(pageID)",
                        severity: .error,
                        message: "Page id is duplicated: \(pageID)."
                    )
                )
            } else {
                seenPageIDs.insert(pageID)
            }

            if page.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(
                    RuleValidationResult.Issue(
                        id: "page-title-empty-\(pageID)",
                        severity: .warning,
                        message: "Page \(pageID.isEmpty ? "(blank)" : pageID) has no title."
                    )
                )
            }

            if page.isListEntryPage,
               page.ruleRefs?.list?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(
                    RuleValidationResult.Issue(
                        id: "page-list-ref-empty-\(pageID)",
                        severity: .warning,
                        message: "List entry page \(pageID.isEmpty ? "(blank)" : pageID) has no list rule reference; legacy list fallback may be used."
                    )
                )
            }
        }
    }

    private func appendRuleSetIssues(rule: SiteRule, issues: inout [RuleValidationResult.Issue]) {
        guard let ruleSets: RuleSets = rule.ruleSets else {
            if let pages: [PageRule] = rule.pages,
               pages.contains(where: { page in
                   return page.ruleRefs != nil
               }) {
                issues.append(
                    RuleValidationResult.Issue(
                        id: "rule-sets-missing",
                        severity: .error,
                        message: "RuleSets are required when V2 pages use ruleRefs."
                    )
                )
            }
            return
        }

        self.appendDuplicateRuleIDIssues(
            kind: "series",
            ids: ruleSets.seriesRules?.compactMap(\.id) ?? [],
            issues: &issues
        )
        self.appendDuplicateRuleIDIssues(
            kind: "list",
            ids: ruleSets.listRules?.compactMap(\.id) ?? [],
            issues: &issues
        )
        self.appendDuplicateRuleIDIssues(
            kind: "detail",
            ids: ruleSets.detailRules?.compactMap(\.id) ?? [],
            issues: &issues
        )
        self.appendDuplicateRuleIDIssues(
            kind: "gallery",
            ids: ruleSets.galleryRules?.compactMap(\.id) ?? [],
            issues: &issues
        )
        self.appendDuplicateRuleIDIssues(
            kind: "search",
            ids: ruleSets.searchRules?.compactMap(\.id) ?? [],
            issues: &issues
        )
    }

    private func appendDuplicateRuleIDIssues(
        kind: String,
        ids: [String],
        issues: inout [RuleValidationResult.Issue]
    ) {
        var seenRuleIDs: Set<String> = []

        for id: String in ids {
            let ruleID: String = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard ruleID.isEmpty == false else {
                continue
            }

            if seenRuleIDs.contains(ruleID) {
                issues.append(
                    RuleValidationResult.Issue(
                        id: "rule-id-duplicate-\(kind)-\(ruleID)",
                        severity: .error,
                        message: "\(kind.capitalized) rule id is duplicated: \(ruleID)."
                    )
                )
            } else {
                seenRuleIDs.insert(ruleID)
            }
        }
    }

    private func appendRuleReferenceIssues(rule: SiteRule, issues: inout [RuleValidationResult.Issue]) {
        guard let pages: [PageRule] = rule.pages,
              let ruleSets: RuleSets = rule.ruleSets else {
            return
        }

        for page: PageRule in pages {
            self.appendMissingRuleIssue(
                pageID: page.id,
                kind: "list",
                ruleID: page.ruleRefs?.list,
                exists: ruleSets.listRule(id: page.ruleRefs?.list) != nil,
                issues: &issues
            )
            self.appendMissingRuleIssue(
                pageID: page.id,
                kind: "detail",
                ruleID: page.ruleRefs?.detail,
                exists: ruleSets.detailRule(id: page.ruleRefs?.detail) != nil,
                issues: &issues
            )
            self.appendMissingRuleIssue(
                pageID: page.id,
                kind: "gallery",
                ruleID: page.ruleRefs?.gallery,
                exists: ruleSets.galleryRule(id: page.ruleRefs?.gallery) != nil,
                issues: &issues
            )
            self.appendMissingRuleIssue(
                pageID: page.id,
                kind: "search",
                ruleID: page.ruleRefs?.search,
                exists: ruleSets.searchRule(id: page.ruleRefs?.search) != nil,
                issues: &issues
            )
        }
    }

    private func appendMissingRuleIssue(
        pageID: String,
        kind: String,
        ruleID: String?,
        exists: Bool,
        issues: inout [RuleValidationResult.Issue]
    ) {
        guard let ruleID: String = ruleID?.trimmingCharacters(in: .whitespacesAndNewlines),
              ruleID.isEmpty == false,
              exists == false else {
            return
        }

        issues.append(
            RuleValidationResult.Issue(
                id: "missing-\(pageID)-\(kind)-\(ruleID)",
                severity: .error,
                message: "Page \(pageID) references missing \(kind) rule: \(ruleID)."
            )
        )
    }

    private func appendPrimaryFlowIssues(rule: SiteRule, issues: inout [RuleValidationResult.Issue]) {
        if rule.availableListTabs.isEmpty {
            issues.append(
                RuleValidationResult.Issue(
                    id: "list-entry-missing",
                    severity: .error,
                    message: "At least one list entry rule is required."
                )
            )
        }

        if rule.primaryDetailRule == nil {
            issues.append(
                RuleValidationResult.Issue(
                    id: "detail-rule-missing",
                    severity: .warning,
                    message: "No detail rule is configured; one-layer reader sources may still work."
                )
            )
        }

        if rule.primaryGalleryRule == nil {
            issues.append(
                RuleValidationResult.Issue(
                    id: "gallery-rule-missing",
                    severity: .warning,
                    message: "No gallery/reader rule is configured."
                )
            )
        }
    }
}

/// 中文注释：更新用户规则；内置规则由 RulesKit 同步，不能被直接覆盖。
struct UpdateSourceRuleUseCase {
    private let sourceRepository: SourceRepository
    private let ruleValidator: RuleValidator

    init(
        sourceRepository: SourceRepository,
        ruleValidator: RuleValidator = RuleValidator()
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

        let validationResult: RuleValidationResult = self.ruleValidator.validate(ruleJSON: ruleJSON)
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
    case validationFailed(RuleValidationResult)
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
