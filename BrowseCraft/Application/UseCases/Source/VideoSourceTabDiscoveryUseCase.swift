import Foundation
import BrowseCraftCore

// 中文注释：视频 tab discovery 使用入口页最终 HTML；当请求配置要求 WebView 时，这里拿到的是 rendered DOM。
struct VideoSourceTabDiscoveryUseCase {
    private let pageContentLoader: PageContentLoader
    private let discovererRegistry: VideoTabDiscovererRegistry
    private let requestConfigResolver: VideoRequestConfigResolver

    init(
        pageContentLoader: PageContentLoader,
        discovererRegistry: VideoTabDiscovererRegistry = VideoTabDiscovererRegistry(),
        requestConfigResolver: VideoRequestConfigResolver = VideoRequestConfigResolver()
    ) {
        self.pageContentLoader = pageContentLoader
        self.discovererRegistry = discovererRegistry
        self.requestConfigResolver = requestConfigResolver
    }

    func discoverTabs(
        sourceID: String,
        definition: VideoSourceDefinition,
        explicitTabs: [VideoSourceListTab]
    ) async throws -> [VideoSourceListTab] {
        // 中文注释：后台目录规则已经给出 tabs 时不要再加载入口页自动发现，避免反爬站点重复触发 WebView。
        guard explicitTabs.isEmpty else {
            return explicitTabs
        }

        let request: RequestConfig? = self.requestConfigResolver.request(
            for: .list,
            definition: definition,
            context: SourceRuntimeContext(
                sourceID: sourceID,
                pageID: "video",
                tabID: nil,
                sectionID: nil,
                sectionRole: nil,
                ruleID: nil,
                requestOverride: nil,
                debugMode: false,
                operation: .list
            )
        )
        let html: String = try await self.pageContentLoader.getString(
            from: definition.entryURL,
            request: request
        )
        let discoveredTabs: [VideoSourceListTab] = try self.discovererRegistry
            .discoverer(for: definition.adapter)
            .discoverTabs(
                html: html,
                definition: definition,
                pageURL: definition.entryURL
            )

        return self.mergedTabs(
            explicitTabs: explicitTabs,
            discoveredTabs: discoveredTabs
        )
    }

    private func mergedTabs(
        explicitTabs: [VideoSourceListTab],
        discoveredTabs: [VideoSourceListTab]
    ) -> [VideoSourceListTab] {
        var tabs: [VideoSourceListTab] = explicitTabs.isEmpty ? [] : explicitTabs
        var seenURLs: Set<String> = Set(tabs.map { tab in
            return self.normalizedURLKey(tab.url)
        })

        for discoveredTab: VideoSourceListTab in discoveredTabs {
            let key: String = self.normalizedURLKey(discoveredTab.url)
            guard seenURLs.contains(key) == false else {
                continue
            }

            seenURLs.insert(key)
            tabs.append(discoveredTab)
        }

        return tabs.isEmpty ? discoveredTabs : tabs
    }

    private func normalizedURLKey(_ string: String) -> String {
        guard var components: URLComponents = URLComponents(string: string) else {
            return string
        }

        components.fragment = nil
        return components.url?.absoluteString ?? string
    }
}
