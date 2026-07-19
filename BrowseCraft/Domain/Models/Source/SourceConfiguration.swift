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

/// 中文注释：P2-6 后视频来源只有 V2 rule-driven 持久化形态；旧 preset 会在数据库迁移中移除。
struct VideoSourceConfiguration: Codable, Hashable {
    static let strategy: String = "ruleDriven"

    var rule: VideoSiteRule

    init(rule: VideoSiteRule) {
        self.rule = rule
    }

    private enum CodingKeys: String, CodingKey {
        case strategy
        case rule
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        let strategy: String? = try container.decodeIfPresent(
            String.self,
            forKey: .strategy
        )

        guard strategy == Self.strategy else {
            throw DecodingError.dataCorruptedError(
                forKey: .strategy,
                in: container,
                debugDescription: "Video V1 configurations are no longer supported."
            )
        }
        self.rule = try container.decode(VideoSiteRule.self, forKey: .rule)
    }

    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.strategy, forKey: .strategy)
        try container.encode(self.rule, forKey: .rule)
    }
}

struct PluginSourceConfiguration: Codable, Hashable {
    var definition: PluginSourceDefinition
}
