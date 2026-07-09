import Foundation

// 中文注释：Source 是 App 侧持久化来源实体，运行入口由 SourceConfiguration 决定。

/// 中文注释：用户添加的内容源模型。
/// 中文注释：Source 是 App 持久化实体；执行语义由 SourceRuntime 决定。
/// 中文注释：Source 的主配置入口是 SourceConfiguration；rule 访问器只用于迁移期兼容旧调用点。
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
            configuration: .comic(
                ComicSourceConfiguration(
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

// 中文注释：SourceSnapshot 保存脱离 sources 表后仍可恢复运行所需的来源配置快照。
struct SourceSnapshot: Hashable, Codable {
    var id: String
    var name: String
    var baseURL: String
    var type: SourceType
    var configuration: SourceConfiguration
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(source: Source) {
        self.id = source.id
        self.name = source.name
        self.baseURL = source.baseURL
        self.type = source.type
        self.configuration = source.configuration
        self.enabled = source.enabled
        self.createdAt = source.createdAt
        self.updatedAt = source.updatedAt
    }

    func source() -> Source {
        return Source(
            id: self.id,
            name: self.name,
            baseURL: self.baseURL,
            type: self.type,
            configuration: self.configuration,
            enabled: self.enabled,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt
        )
    }
}

extension Source {
    var comicConfiguration: ComicSourceConfiguration? {
        guard case .comic(let configuration) = self.configuration else {
            return nil
        }

        return configuration
    }

    var ruleConfiguration: ComicSourceConfiguration? {
        return self.comicConfiguration
    }

    var rule: SiteRule {
        get {
            guard let rule: SiteRule = self.ruleConfiguration?.rule else {
                preconditionFailure("source.rule is only available for comic sources backed by SiteRule")
            }

            return rule
        }
        set {
            let currentConfiguration: ComicSourceConfiguration? = self.comicConfiguration
            self.configuration = .comic(
                ComicSourceConfiguration(
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

    var favoriteVideoKind: FavoriteContentKind? {
        guard case .video(let configuration) = self.configuration else {
            return nil
        }

        return configuration.definition.adapter == .webView ? .videoWeb : .videoNative
    }
}
