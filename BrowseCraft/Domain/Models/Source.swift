import Foundation

// 中文注释：Source.swift 属于领域模型层，用于说明本文件承载的核心职责。

/// 中文注释：用户添加的内容源模型。
/// 中文注释：Source 是 App 持久化实体；执行语义由 SourceRuntime 决定。
/// 现阶段 rule-backed source 仍持有 SiteRule JSON，RSS/Plugin 后续应进入各自 runtime config。
struct Source: Identifiable, Hashable {
    var id: String
    var name: String
    var baseURL: String
    var type: SourceType
    var rule: SiteRule
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date
}

extension Source {
    var configuration: SourceConfiguration {
        return .rule(
            RuleSourceConfiguration(
                rule: self.rule,
                schemaVersion: self.rule.version ?? 1,
                packageMetadata: nil,
                isEditable: self.isBuiltIn == false
            )
        )
    }

    /// 中文注释：内置规则由 BrowseCraftRulesKit 同步，编辑器只能复制后修改，避免刷新时覆盖用户改动。
    var isBuiltIn: Bool {
        return self.id.hasPrefix("built-in.")
    }
}
