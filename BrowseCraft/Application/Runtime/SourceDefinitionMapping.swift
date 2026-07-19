import Foundation
import BrowseCraftCore

// 中文注释：SourceDefinitionMapper 是 runtime-neutral 映射边界；具体执行配置仍留在 SourceConfiguration。
struct SourceDefinitionMapper {
    func definition(from source: Source) -> SourceDefinition {
        return self.definition(
            id: source.id,
            name: source.name,
            baseURL: source.baseURL,
            version: source.ruleConfiguration?.rule.version,
            ownership: self.ownership(for: source),
            configuration: source.configuration
        )
    }

    func definition(
        id: String,
        name: String,
        baseURL: String,
        version: Int?,
        ownership: SourceOwnership,
        configuration: SourceConfiguration
    ) -> SourceDefinition {
        switch configuration {
        case .comic(let ruleConfiguration):
            return SourceDefinition(
                id: id,
                runtimeKind: .comic,
                name: name,
                baseURL: self.baseURL(from: baseURL),
                version: version ?? ruleConfiguration.rule.version,
                ownership: ownership,
                comic: RuleBackedSourceDefinition(
                    ruleID: id,
                    schemaVersion: ruleConfiguration.schemaVersion,
                    packageMetadata: ruleConfiguration.packageMetadata,
                    isEditable: ruleConfiguration.isEditable
                ),
                rss: nil,
                plugin: nil
            )
        case .rss(let rssConfiguration):
            return SourceDefinition(
                id: id,
                runtimeKind: .rss,
                name: name,
                baseURL: self.baseURL(from: baseURL),
                version: version,
                ownership: ownership,
                comic: nil,
                rss: rssConfiguration.definition,
                plugin: nil
            )
        case .video(let videoConfiguration):
            return SourceDefinition(
                id: id,
                runtimeKind: .video,
                name: name,
                baseURL: self.baseURL(from: baseURL),
                version: videoConfiguration.rule.version,
                ownership: ownership,
                comic: nil,
                rss: nil,
                plugin: nil
            )
        case .plugin(let pluginConfiguration):
            return SourceDefinition(
                id: id,
                runtimeKind: .plugin,
                name: name,
                baseURL: self.baseURL(from: baseURL),
                version: version,
                ownership: ownership,
                comic: nil,
                rss: nil,
                plugin: pluginConfiguration.definition
            )
        }
    }

    private func baseURL(from string: String) -> URL {
        let normalizedString: String = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedString.isEmpty == false,
           let url: URL = URL(string: normalizedString) {
            return url
        }

        if let placeholderURL: URL = URL(string: "about:blank") {
            return placeholderURL
        }

        return URL(fileURLWithPath: "/")
    }

    private func ownership(for source: Source) -> SourceOwnership {
        if source.isBuiltIn {
            return .builtIn
        }

        return .user
    }

}
