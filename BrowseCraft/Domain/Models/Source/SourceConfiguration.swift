import Foundation
import BrowseCraftCore

// 中文注释：SourceConfiguration 是长期 source config 边界；旧 source.rule 只是 rule 迁移期兼容入口。
enum SourceConfiguration: Codable, Hashable {
    case rule(RuleSourceConfiguration)
    case rss(RSSSourceConfiguration)
    case plugin(PluginSourceConfiguration)

    var kind: SourceDefinitionKind {
        switch self {
        case .rule:
            return .rule
        case .rss:
            return .rss
        case .plugin:
            return .plugin
        }
    }
}

struct RuleSourceConfiguration: Codable, Hashable {
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
