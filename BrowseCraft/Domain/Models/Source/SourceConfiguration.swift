import Foundation
import BrowseCraftCore

// 中文注释：SourceConfiguration 是长期 source config 边界；漫画配置内部仍可由网站规则驱动。
enum SourceConfiguration: Codable, Hashable {
    case comic(ComicSourceConfiguration)
    case rss(RSSSourceConfiguration)
    case plugin(PluginSourceConfiguration)

    var kind: SourceRuntimeKind {
        switch self {
        case .comic:
            return .comic
        case .rss:
            return .rss
        case .plugin:
            return .plugin
        }
    }

    private enum CodingKeys: String, CodingKey {
        case comic
        case legacyRule = "rule"
        case rss
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

struct PluginSourceConfiguration: Codable, Hashable {
    var definition: PluginSourceDefinition
}
