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
                video: nil,
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
                video: nil,
                plugin: nil
            )
        case .video(let videoConfiguration):
            return SourceDefinition(
                id: id,
                runtimeKind: .video,
                name: name,
                baseURL: self.baseURL(from: baseURL),
                version: videoConfiguration.ruleDrivenConfiguration?.rule.version ?? version,
                ownership: ownership,
                comic: nil,
                rss: nil,
                video: videoConfiguration.legacyConfiguration.map { legacyConfiguration in
                    return self.normalizedVideoDefinition(from: legacyConfiguration)
                },
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
                video: nil,
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

    private func normalizedVideoDefinition(
        from configuration: VideoLegacySourceConfiguration
    ) -> VideoSourceDefinition {
        let definition: VideoSourceDefinition = configuration.definition
        guard definition.adapter == .genericHTML,
              self.hasMacCMSRoutePatternSignals(definition: definition, listTabs: configuration.listTabs) else {
            return definition
        }

        return VideoSourceDefinition(
            adapter: .macCMS,
            entryURL: definition.entryURL,
            seedURL: definition.seedURL,
            entryKind: definition.entryKind,
            routePatterns: definition.routePatterns ?? .macCMS,
            playbackPolicy: definition.playbackPolicy,
            sharedRequest: definition.sharedRequest,
            listRequest: definition.listRequest,
            detailRequest: definition.detailRequest,
            playRequest: definition.playRequest,
            requiresAccount: definition.requiresAccount,
            seedVodID: definition.seedVodID,
            seedSourceIndex: definition.seedSourceIndex,
            seedEpisodeIndex: definition.seedEpisodeIndex,
            seedDetailURL: definition.seedDetailURL,
            seedPlayURL: definition.seedPlayURL
        )
    }

    private func hasMacCMSRoutePatternSignals(
        definition: VideoSourceDefinition,
        listTabs: [VideoSourceListTab]
    ) -> Bool {
        if definition.routePatterns == .macCMS {
            return true
        }

        var parts: [String] = [
            definition.entryURL.absoluteString,
            definition.seedURL?.absoluteString ?? "",
            definition.seedDetailURL?.absoluteString ?? "",
            definition.seedPlayURL?.absoluteString ?? ""
        ]
        for tab: VideoSourceListTab in listTabs {
            parts.append(tab.url)
            parts.append(tab.itemSelector ?? "")
            parts.append(tab.titleSelector ?? "")
            parts.append(tab.linkSelector ?? "")
            parts.append(tab.coverSelector ?? "")
            parts.append(tab.latestTextSelector ?? "")
        }

        let text: String = parts.joined(separator: "\n").lowercased()
        return self.hasStrongMacCMSTemplateMarkers(text)
            || self.hasMacCMSRouteCluster(text)
            || self.hasMacCMSCategoryRouteCluster(in: parts)
    }

    private func hasStrongMacCMSTemplateMarkers(_ text: String) -> Bool {
        let markers: [String] = [
            "/template/vfed/",
            "var vfed",
            "fed-list-item",
            "fed-list-pics",
            "fed-list-title",
            "fed-play-item",
            "fed-part-rows",
            "player_aaaa"
        ]
        let count: Int = markers.reduce(into: 0) { result, marker in
            if text.contains(marker) {
                result += 1
            }
        }
        return count >= 2
    }

    private func hasMacCMSRouteCluster(_ text: String) -> Bool {
        return text.contains("/voddetail/") && text.contains("/vodplay/")
    }

    private func hasMacCMSCategoryRouteCluster(in values: [String]) -> Bool {
        let categoryRoutes: Set<String> = Set(values.compactMap { value in
            guard let url: URL = URL(string: value),
                  let route: String = self.macCMSCategoryRoute(from: url.path) else {
                return nil
            }
            return route
        })
        return categoryRoutes.count >= 2
    }

    private func macCMSCategoryRoute(from path: String) -> String? {
        let normalizedPath: String = path.lowercased()
        guard normalizedPath.hasPrefix("/vodtype/")
            || normalizedPath.hasPrefix("/vodshow/") else {
            return nil
        }
        return normalizedPath
    }
}
