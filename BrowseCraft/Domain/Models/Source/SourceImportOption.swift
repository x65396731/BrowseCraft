import Foundation
import BrowseCraftCore
import BrowseCraftDomain

// 中文注释：SourceImportOption 表达添加来源流程中用户可选择的入口方式，并给出默认 runtime kind。
struct SourceImportOption: Identifiable, Codable, Hashable, Sendable {
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

/// 中文注释：只剩三种可生成的 kind。`scriptSource` 已随规则 JSON 导入一并下线（`BCA-UI-003`），
/// 它在界面上早就到不了，只剩一个英文提示框。
enum SourceImportOptionKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case comicSource
    case videoSource
    case bookSource

    var id: String {
        return self.rawValue
    }
}

extension SourceImportOption {
    /// 中文注释：顺序与添加来源页、收藏页、历史页一致：视频、漫画、书籍。
    static let defaultOptions: [SourceImportOption] = [
        SourceImportOption(
            kind: .videoSource,
            defaultSourceType: .html,
            defaultConfigurationKind: .video
        ),
        SourceImportOption(
            kind: .comicSource,
            defaultSourceType: .html,
            defaultConfigurationKind: .comic
        ),
        SourceImportOption(
            kind: .bookSource,
            defaultSourceType: .html,
            defaultConfigurationKind: .book
        )
    ]

    var requiresURLInput: Bool {
        switch self.kind {
        case .comicSource, .videoSource, .bookSource:
            return false
        }
    }

    var acceptsRuleJSONInput: Bool {
        switch self.kind {
        case .comicSource, .videoSource, .bookSource:
            return false
        }
    }
}
