import BrowseCraftCore
import Foundation

// 中文注释：RuleManagementUseCases.swift 承载 P2-1 规则管理的校验、更新和复制用例。

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

/// 中文注释：更新用户视频源配置；内置源仍只读，避免 catalog/built-in 同步覆盖用户修改。
struct UpdateVideoSourceConfigurationUseCase {
    private let sourceRepository: SourceRepository
    private let jsonDecoder: JSONDecoder
    private let videoRuleValidator: VideoSiteRuleValidator

    init(
        sourceRepository: SourceRepository,
        jsonDecoder: JSONDecoder = JSONDecoder(),
        videoRuleValidator: VideoSiteRuleValidator = VideoSiteRuleValidator()
    ) {
        self.sourceRepository = sourceRepository
        self.jsonDecoder = jsonDecoder
        self.videoRuleValidator = videoRuleValidator
    }

    func execute(source: Source, configurationJSON: String, expectedUpdatedAt: Date? = nil) throws -> Source {
        let latestSource: Source = try self.latestSource(matching: source) ?? source

        guard latestSource.isBuiltIn == false else {
            throw RuleManagementError.builtInSourceIsReadOnly
        }

        if let expectedUpdatedAt: Date = expectedUpdatedAt,
           latestSource.updatedAt != expectedUpdatedAt {
            throw RuleManagementError.sourceChanged
        }

        guard case .video = latestSource.configuration else {
            throw RuleManagementError.unsupportedSourceConfiguration
        }

        let configuration: VideoSourceConfiguration = try self.validatedConfiguration(
            from: configurationJSON
        )

        var updatedSource: Source = latestSource
        updatedSource.configuration = .video(configuration)
        switch configuration {
        case .legacyPreset(let legacyConfiguration):
            updatedSource.baseURL = self.baseURLString(from: legacyConfiguration.definition.entryURL)
        case .ruleDriven(let ruleConfiguration):
            updatedSource.name = ruleConfiguration.rule.name
            updatedSource.baseURL = ruleConfiguration.rule.baseUrl
        }
        updatedSource.updatedAt = Date()
        try self.sourceRepository.saveSource(updatedSource)
        return updatedSource
    }

    /// 中文注释：编辑器预检查与保存共用同一入口，避免 Codable 忽略未知 V2 字段后出现假阳性。
    func validate(configurationJSON: String) throws {
        _ = try self.validatedConfiguration(from: configurationJSON)
    }

    private func latestSource(matching source: Source) throws -> Source? {
        return try self.sourceRepository.fetchSources().first { candidate in
            return candidate.id == source.id
        }
    }

    private func baseURLString(from entryURL: URL) -> String {
        var components: URLComponents? = URLComponents(url: entryURL, resolvingAgainstBaseURL: false)
        components?.path = "/"
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString ?? entryURL.absoluteString
    }

    private func validatedConfiguration(
        from configurationJSON: String
    ) throws -> VideoSourceConfiguration {
        let configuration: VideoSourceConfiguration = try self.jsonDecoder.decode(
            VideoSourceConfiguration.self,
            from: Data(configurationJSON.utf8)
        )
        guard case .ruleDriven = configuration else {
            return configuration
        }

        let rawRuleJSON: String = try self.ruleJSON(from: configurationJSON)
        let validationResult: VideoSiteRuleValidationResult = self.videoRuleValidator.validate(
            ruleJSON: rawRuleJSON
        )
        guard validationResult.canImport else {
            throw RuleManagementError.videoValidationFailed(validationResult)
        }
        return configuration
    }

    /// 中文注释：编辑 V2 configuration 时重新取出原始 rule 对象，确保未知字段不会被 Codable 静默丢弃。
    private func ruleJSON(from configurationJSON: String) throws -> String {
        let rawValue: Any = try JSONSerialization.jsonObject(with: Data(configurationJSON.utf8))
        guard let configuration: [String: Any] = rawValue as? [String: Any],
              configuration["strategy"] as? String == VideoSourceConfigurationStrategy.ruleDriven.rawValue,
              let rule: [String: Any] = configuration["rule"] as? [String: Any] else {
            throw RuleManagementError.unsupportedSourceConfiguration
        }
        let ruleData: Data = try JSONSerialization.data(
            withJSONObject: rule,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard let ruleJSON: String = String(data: ruleData, encoding: .utf8) else {
            throw RuleManagementError.unsupportedSourceConfiguration
        }
        return ruleJSON
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
    case videoValidationFailed(VideoSiteRuleValidationResult)
    case sourceChanged
    case unsupportedSourceConfiguration

    var errorDescription: String? {
        switch self {
        case .builtInSourceIsReadOnly:
            return "Built-in rules are read-only. Duplicate the rule before editing."
        case .validationFailed(let result):
            return result.errors.first?.message ?? "Rule validation failed."
        case .videoValidationFailed(let result):
            return result.errors.first?.message ?? "Video V2 validation failed."
        case .sourceChanged:
            return "This source changed after the editor was opened. Reopen the editor before saving."
        case .unsupportedSourceConfiguration:
            return "This source configuration cannot be edited here."
        }
    }
}
