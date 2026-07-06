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

struct VideoSourceConfiguration: Codable, Hashable {
    var definition: VideoSourceDefinition
    var listTabs: [VideoSourceListTab]

    init(
        definition: VideoSourceDefinition,
        listTabs: [VideoSourceListTab] = []
    ) {
        self.definition = definition
        self.listTabs = listTabs
    }

    private enum CodingKeys: String, CodingKey {
        case definition
        case listTabs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.definition = try container.decode(VideoSourceDefinition.self, forKey: .definition)
        self.listTabs = try container.decodeIfPresent([VideoSourceListTab].self, forKey: .listTabs) ?? []
    }
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
