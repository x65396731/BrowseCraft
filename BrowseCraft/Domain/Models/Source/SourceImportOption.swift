import Foundation
import BrowseCraftCore

// 中文注释：SourceImportOption 表达添加来源流程中用户可选择的入口方式，并给出默认 runtime kind。
struct SourceImportOption: Identifiable, Codable, Hashable {
    var kind: SourceImportOptionKind
    var defaultSourceType: SourceType?
    var defaultConfigurationKind: SourceRuntimeKind?

    var id: SourceImportOptionKind {
        return self.kind
    }

    init(
        kind: SourceImportOptionKind,
        defaultSourceType: SourceType? = nil,
        defaultConfigurationKind: SourceRuntimeKind? = nil
    ) {
        self.kind = kind
        self.defaultSourceType = defaultSourceType
        self.defaultConfigurationKind = defaultConfigurationKind
    }
}

enum SourceImportOptionKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case comicSource
    case videoSource
    case rssFeedURL
    case scriptSource

    var id: String {
        return self.rawValue
    }
}

extension SourceImportOption {
    static let defaultOptions: [SourceImportOption] = [
        SourceImportOption(
            kind: .comicSource,
            defaultSourceType: .html,
            defaultConfigurationKind: .comic
        ),
        SourceImportOption(
            kind: .videoSource,
            defaultSourceType: .html,
            defaultConfigurationKind: .video
        ),
        SourceImportOption(
            kind: .rssFeedURL,
            defaultSourceType: .rss,
            defaultConfigurationKind: .rss
        )
    ]

    var requiresURLInput: Bool {
        switch self.kind {
        case .rssFeedURL:
            return true
        case .comicSource, .videoSource, .scriptSource:
            return false
        }
    }

    var acceptsRuleJSONInput: Bool {
        switch self.kind {
        case .comicSource, .videoSource, .rssFeedURL, .scriptSource:
            return false
        }
    }
}
