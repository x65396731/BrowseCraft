import Foundation
import BrowseCraftCore

// 中文注释：SourceConfiguration 是长期 source config 边界；漫画配置内部仍可由网站规则驱动。
enum SourceConfiguration: Codable, Hashable {
    case comic(ComicSourceConfiguration)
    case rss(RSSSourceConfiguration)
    case video(VideoSourceConfiguration)
    case plugin(PluginSourceConfiguration)

    var kind: SourceRuntimeKind {
        switch self {
        case .comic:
            return .comic
        case .rss:
            return .rss
        case .video:
            return .video
        case .plugin:
            return .plugin
        }
    }

    private enum CodingKeys: String, CodingKey {
        case comic
        case legacyRule = "rule"
        case rss
        case video
        case plugin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let configuration: ComicSourceConfiguration = try Self.decodeAssociatedValue(
            ComicSourceConfiguration.self,
            from: container,
            forKey: .comic
        ) {
            self = .comic(configuration)
            return
        }

        if let configuration: ComicSourceConfiguration = try Self.decodeAssociatedValue(
            ComicSourceConfiguration.self,
            from: container,
            forKey: .legacyRule
        ) {
            self = .comic(configuration)
            return
        }

        if let configuration: RSSSourceConfiguration = try Self.decodeAssociatedValue(
            RSSSourceConfiguration.self,
            from: container,
            forKey: .rss
        ) {
            self = .rss(configuration)
            return
        }

        if let configuration: VideoSourceConfiguration = try Self.decodeAssociatedValue(
            VideoSourceConfiguration.self,
            from: container,
            forKey: .video
        ) {
            self = .video(configuration)
            return
        }

        if let configuration: PluginSourceConfiguration = try Self.decodeAssociatedValue(
            PluginSourceConfiguration.self,
            from: container,
            forKey: .plugin
        ) {
            self = .plugin(configuration)
            return
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported source configuration."
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .comic(let configuration):
            try container.encode(configuration, forKey: .comic)
        case .rss(let configuration):
            try container.encode(configuration, forKey: .rss)
        case .video(let configuration):
            try container.encode(configuration, forKey: .video)
        case .plugin(let configuration):
            try container.encode(configuration, forKey: .plugin)
        }
    }

    private static func decodeAssociatedValue<Value: Decodable>(
        _ valueType: Value.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Value? {
        _ = valueType

        if let value: Value = try? container.decodeIfPresent(Value.self, forKey: key) {
            return value
        }

        if let legacyValue: LegacyAssociatedValue<Value> = try? container.decodeIfPresent(
            LegacyAssociatedValue<Value>.self,
            forKey: key
        ) {
            return legacyValue.value
        }

        return nil
    }
}

private struct LegacyAssociatedValue<Value: Decodable>: Decodable {
    let value: Value

    private enum CodingKeys: String, CodingKey {
        case value = "_0"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.value = try container.decode(Value.self, forKey: .value)
    }
}

struct ComicSourceConfiguration: Codable, Hashable {
    var rule: SiteRule
    var schemaVersion: Int
    var packageMetadata: BrowseCraftCore.RulePackageMetadata?
    var isEditable: Bool
}

struct RSSSourceConfiguration: Codable, Hashable {
    var definition: RSSSourceDefinition
}

/// 中文注释：视频持久化显式区分 V2 rule-driven 与隔离的 V1 preset，避免 V2 被旧 adapter 静默接管。
enum VideoSourceConfiguration: Codable, Hashable {
    case legacyPreset(VideoLegacySourceConfiguration)
    case ruleDriven(VideoRuleDrivenSourceConfiguration)

    var strategy: VideoSourceConfigurationStrategy {
        switch self {
        case .legacyPreset:
            return .legacyPreset
        case .ruleDriven:
            return .ruleDriven
        }
    }

    var legacyConfiguration: VideoLegacySourceConfiguration? {
        guard case .legacyPreset(let configuration) = self else {
            return nil
        }
        return configuration
    }

    var ruleDrivenConfiguration: VideoRuleDrivenSourceConfiguration? {
        guard case .ruleDriven(let configuration) = self else {
            return nil
        }
        return configuration
    }

    /// 中文注释：保留旧构造入口，现有手动视频来源明确进入 legacyPreset，不把它误标为 V2。
    init(
        definition: VideoSourceDefinition,
        listTabs: [VideoSourceListTab] = []
    ) {
        self = .legacyPreset(
            VideoLegacySourceConfiguration(
                definition: definition,
                listTabs: listTabs
            )
        )
    }

    init(rule: VideoSiteRule) {
        self = .ruleDriven(VideoRuleDrivenSourceConfiguration(rule: rule))
    }

    private enum CodingKeys: String, CodingKey {
        case strategy
        case definition
        case listTabs
        case rule
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        let strategy: VideoSourceConfigurationStrategy? = try container.decodeIfPresent(
            VideoSourceConfigurationStrategy.self,
            forKey: .strategy
        )

        switch strategy {
        case .some(.legacyPreset), .none:
            guard container.contains(.rule) == false else {
                throw DecodingError.dataCorruptedError(
                    forKey: .rule,
                    in: container,
                    debugDescription: "Legacy video configuration must not contain a V2 rule."
                )
            }
            self = .legacyPreset(
                VideoLegacySourceConfiguration(
                    definition: try container.decode(VideoSourceDefinition.self, forKey: .definition),
                    listTabs: try container.decodeIfPresent([VideoSourceListTab].self, forKey: .listTabs) ?? []
                )
            )
        case .some(.ruleDriven):
            guard container.contains(.definition) == false,
                  container.contains(.listTabs) == false else {
                throw DecodingError.dataCorruptedError(
                    forKey: .strategy,
                    in: container,
                    debugDescription: "Rule-driven video configuration must not contain legacy definition/listTabs."
                )
            }
            self = .ruleDriven(
                VideoRuleDrivenSourceConfiguration(
                    rule: try container.decode(VideoSiteRule.self, forKey: .rule)
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.strategy, forKey: .strategy)

        switch self {
        case .legacyPreset(let configuration):
            try container.encode(configuration.definition, forKey: .definition)
            if configuration.listTabs.isEmpty == false {
                try container.encode(configuration.listTabs, forKey: .listTabs)
            }
        case .ruleDriven(let configuration):
            try container.encode(configuration.rule, forKey: .rule)
        }
    }
}

enum VideoSourceConfigurationStrategy: String, Codable, Hashable {
    case legacyPreset
    case ruleDriven
}

struct VideoLegacySourceConfiguration: Hashable {
    var definition: VideoSourceDefinition
    var listTabs: [VideoSourceListTab]
}

struct VideoRuleDrivenSourceConfiguration: Hashable {
    var rule: VideoSiteRule
}

struct VideoSourceListTab: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var url: String
    var role: SectionRole?
    var itemSelector: String?
    var titleSelector: String?
    var linkSelector: String?
    var coverSelector: String?
    var latestTextSelector: String?

    init(
        id: String,
        title: String,
        url: String,
        role: SectionRole? = .main,
        itemSelector: String? = nil,
        titleSelector: String? = nil,
        linkSelector: String? = nil,
        coverSelector: String? = nil,
        latestTextSelector: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.role = role
        self.itemSelector = itemSelector
        self.titleSelector = titleSelector
        self.linkSelector = linkSelector
        self.coverSelector = coverSelector
        self.latestTextSelector = latestTextSelector
    }
}

struct PluginSourceConfiguration: Codable, Hashable {
    var definition: PluginSourceDefinition
}
