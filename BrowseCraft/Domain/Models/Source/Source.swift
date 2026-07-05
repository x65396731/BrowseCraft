import Foundation

// 中文注释：Source.swift 属于领域模型层，用于说明本文件承载的核心职责。

/// 中文注释：用户添加的内容源模型。
/// 中文注释：Source 是 App 持久化实体；执行语义由 SourceRuntime 决定。
/// Source 的主配置入口是 SourceConfiguration；rule 访问器只用于迁移期兼容旧调用点。
struct Source: Identifiable, Hashable {
    var id: String
    var name: String
    var baseURL: String
    var type: SourceType
    var configuration: SourceConfiguration
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        name: String,
        baseURL: String,
        type: SourceType,
        configuration: SourceConfiguration,
        enabled: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.type = type
        self.configuration = configuration
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(
        id: String,
        name: String,
        baseURL: String,
        type: SourceType,
        rule: SiteRule,
        enabled: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.init(
            id: id,
            name: name,
            baseURL: baseURL,
            type: type,
            configuration: .rule(
                RuleSourceConfiguration(
                    rule: rule,
                    schemaVersion: rule.version ?? 1,
                    packageMetadata: nil,
                    isEditable: id.hasPrefix("built-in.") == false
                )
            ),
            enabled: enabled,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension Source {
    var ruleConfiguration: RuleSourceConfiguration? {
        guard case .rule(let configuration) = self.configuration else {
            return nil
        }

        return configuration
    }

    var rule: SiteRule {
        get {
            guard let rule: SiteRule = self.ruleConfiguration?.rule else {
                preconditionFailure("source.rule is only available for rule-backed sources")
            }

            return rule
        }
        set {
            let currentConfiguration: RuleSourceConfiguration? = self.ruleConfiguration
            self.configuration = .rule(
                RuleSourceConfiguration(
                    rule: newValue,
                    schemaVersion: newValue.version ?? currentConfiguration?.schemaVersion ?? 1,
                    packageMetadata: currentConfiguration?.packageMetadata,
                    isEditable: currentConfiguration?.isEditable ?? (self.isBuiltIn == false)
                )
            )
        }
    }

    /// 中文注释：内置规则由 BrowseCraftRulesKit 同步，编辑器只能复制后修改，避免刷新时覆盖用户改动。
    var isBuiltIn: Bool {
        return self.id.hasPrefix("built-in.")
    }
}
