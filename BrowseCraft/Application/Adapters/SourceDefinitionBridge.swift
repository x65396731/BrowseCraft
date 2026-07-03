import Foundation
import BrowseCraftCore

// 中文注释：SourceDefinitionBridge 是 P3 的 App -> Core 边界，不改变现有解析流程。
struct SourceDefinitionBridge {
    func definition(from source: Source) -> SourceDefinition {
        return SourceDefinition(
            id: source.id,
            kind: .rule,
            name: source.name,
            baseURL: self.baseURL(from: source.baseURL),
            version: source.rule.version,
            ownership: self.ownership(for: source),
            rule: RuleSourceDefinition(
                ruleID: source.id,
                schemaVersion: source.rule.version ?? 1,
                packageMetadata: nil,
                isEditable: source.isBuiltIn == false
            ),
            rss: nil,
            plugin: nil
        )
    }

    private func baseURL(from string: String) -> URL {
        let normalizedString: String = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedString.isEmpty == false,
           let url: URL = URL(string: normalizedString) {
            return url
        }

        return URL(string: "about:blank")!
    }

    private func ownership(for source: Source) -> SourceOwnership {
        if source.isBuiltIn {
            return .builtIn
        }

        return .user
    }
}
