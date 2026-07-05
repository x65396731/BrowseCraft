import Foundation
import BrowseCraftCore

// 中文注释：SourceImportOption 表达添加来源流程中用户可选择的入口方式。
struct SourceImportOption: Identifiable, Codable, Hashable {
    var kind: SourceImportOptionKind
    var defaultContentType: ContentType?
    var defaultSourceType: SourceType?
    var defaultConfigurationKind: SourceDefinitionKind?

    var id: SourceImportOptionKind {
        return self.kind
    }

    init(
        kind: SourceImportOptionKind,
        defaultContentType: ContentType? = nil,
        defaultSourceType: SourceType? = nil,
        defaultConfigurationKind: SourceDefinitionKind? = nil
    ) {
        self.kind = kind
        self.defaultContentType = defaultContentType
        self.defaultSourceType = defaultSourceType
        self.defaultConfigurationKind = defaultConfigurationKind
    }
}

enum SourceImportOptionKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case websiteURL
    case websiteRuleJSON
    case rulePackageJSON
    case rssFeedURL
    case scriptSource

    var id: String {
        return self.rawValue
    }
}

extension SourceImportOption {
    static let defaultOptions: [SourceImportOption] = [
        SourceImportOption(
            kind: .websiteURL,
            defaultContentType: nil,
            defaultSourceType: .html,
            defaultConfigurationKind: nil
        ),
        SourceImportOption(
            kind: .websiteRuleJSON,
            defaultContentType: nil,
            defaultSourceType: .json,
            defaultConfigurationKind: .rule
        ),
        SourceImportOption(
            kind: .rulePackageJSON,
            defaultContentType: nil,
            defaultSourceType: .json,
            defaultConfigurationKind: .rule
        ),
        SourceImportOption(
            kind: .rssFeedURL,
            defaultContentType: .article,
            defaultSourceType: .rss,
            defaultConfigurationKind: .rss
        ),
        SourceImportOption(
            kind: .scriptSource,
            defaultContentType: nil,
            defaultSourceType: .json,
            defaultConfigurationKind: .plugin
        )
    ]

    var requiresURLInput: Bool {
        switch self.kind {
        case .websiteURL, .rssFeedURL:
            return true
        case .websiteRuleJSON, .rulePackageJSON, .scriptSource:
            return false
        }
    }

    var acceptsRuleJSONInput: Bool {
        switch self.kind {
        case .websiteRuleJSON, .rulePackageJSON:
            return true
        case .websiteURL, .rssFeedURL, .scriptSource:
            return false
        }
    }
}
