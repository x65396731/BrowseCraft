import Foundation
import BrowseCraftCore

// 中文注释：SourceImportDraft 表达“添加来源”流程中的临时草稿，不等同于已保存 Source。
struct SourceImportDraft: Codable, Hashable {
    var name: String
    var entryURL: String
    var contentType: ContentType?
    var sourceType: SourceType?
    var configurationKind: SourceDefinitionKind?
    var ruleJSON: String?

    init(
        name: String = "",
        entryURL: String = "",
        contentType: ContentType? = nil,
        sourceType: SourceType? = nil,
        configurationKind: SourceDefinitionKind? = nil,
        ruleJSON: String? = nil
    ) {
        self.name = name
        self.entryURL = entryURL
        self.contentType = contentType
        self.sourceType = sourceType
        self.configurationKind = configurationKind
        self.ruleJSON = ruleJSON
    }
}

extension SourceImportDraft {
    var trimmedName: String {
        return self.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedEntryURL: String {
        return self.entryURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedRuleJSON: String? {
        let value: String = self.ruleJSON?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    var hasMinimumEntryInput: Bool {
        return self.trimmedEntryURL.isEmpty == false || self.trimmedRuleJSON != nil
    }

    var usesRuleConfiguration: Bool {
        return self.configurationKind == .rule || self.trimmedRuleJSON != nil
    }
}
