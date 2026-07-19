import Foundation

// 中文注释：ResolveLibrarySourcePresentationUseCase 是 Library 展示层边界，不执行 rule runtime。
struct ResolveLibrarySourcePresentationUseCase {
    func listTabs(for source: Source?) -> [ListTabRule] {
        guard let source: Source = source else {
            return []
        }

        if case .video(let configuration) = source.configuration {
            return self.videoListTabs(for: configuration)
        }

        guard let rule: SiteRule = source.ruleConfiguration?.rule else {
            return []
        }

        return rule.availableListTabs
    }

    func imageRequestConfig(for source: Source, listTab: ListTabRule?) -> RequestConfig? {
        if case .video(let configuration) = source.configuration {
            return self.videoImageRequestConfig(for: configuration, listTab: listTab)
        }

        guard let rule: SiteRule = source.ruleConfiguration?.rule else {
            return nil
        }

        return rule.request(for: listTab)
    }

    private func videoImageRequestConfig(
        for configuration: VideoSourceConfiguration,
        listTab: ListTabRule?
    ) -> RequestConfig? {
        switch configuration {
        case .legacyPreset(let legacyConfiguration):
            return RequestConfigResolver().resolve(
                legacyConfiguration.definition.sharedRequest,
                legacyConfiguration.definition.listRequest
            )
        case .ruleDriven(let ruleConfiguration):
            guard let resolvedRule: ResolvedVideoSiteRule = try? ResolvedVideoSiteRule(
                validating: ruleConfiguration.rule
            ) else {
                return nil
            }
            let pageID: String? = listTab?.context?.pageId
            let entry: ResolvedVideoListEntry? = resolvedRule.listEntries.first { entry in
                return pageID == nil || entry.pageID == pageID
            }
            return entry?.effectiveRequest
        }
    }

    private func videoListTabs(for configuration: VideoSourceConfiguration) -> [ListTabRule] {
        switch configuration {
        case .legacyPreset(let legacyConfiguration):
            let tabs: [VideoSourceListTab]
            if legacyConfiguration.listTabs.isEmpty {
                tabs = [
                    VideoSourceListTab(
                        id: "video.home",
                        title: "首页",
                        url: legacyConfiguration.definition.entryURL.absoluteString
                    )
                ]
            } else {
                tabs = legacyConfiguration.listTabs
            }
            return tabs.map(self.videoListTab(_:))

        case .ruleDriven(let ruleConfiguration):
            return ruleConfiguration.rule.pages.map { page in
                let listRuleID: String = page.ruleRefs.list
                return ListTabRule(
                    id: page.id,
                    title: page.title,
                    list: ListRule(
                        id: listRuleID,
                        url: page.url,
                        item: "",
                        title: "",
                        link: "",
                        type: .video
                    ),
                    request: page.request,
                    context: ListContext(
                        pageId: page.id,
                        tabId: page.id,
                        sectionId: nil,
                        listRuleId: listRuleID,
                        sectionRole: .main
                    )
                )
            }
        }
    }

    private func videoListTab(_ tab: VideoSourceListTab) -> ListTabRule {
        return ListTabRule(
            id: tab.id,
            title: tab.title,
            list: ListRule(
                id: tab.id,
                url: tab.url,
                item: tab.itemSelector ?? "",
                title: tab.titleSelector ?? "",
                link: tab.linkSelector ?? "",
                cover: tab.coverSelector,
                type: .video,
                latestText: tab.latestTextSelector
            ),
            context: ListContext(
                pageId: "video",
                tabId: tab.id,
                sectionId: nil,
                listRuleId: tab.id,
                sectionRole: tab.role
            )
        )
    }

    func shouldOpenReaderDirectly(for source: Source) -> Bool {
        guard let rule: SiteRule = source.ruleConfiguration?.rule else {
            return false
        }

        return RuleResolver().resolve(rule).treatsDetailURLAsChapter
    }

    func listContext(from listTab: ListTabRule?) -> ListContext? {
        guard let listTab: ListTabRule = listTab else {
            return nil
        }

        if var context: ListContext = listTab.context {
            if context.listRuleId == nil {
                context.listRuleId = listTab.list.id
            }

            return context
        }

        return ListContext(
            pageId: listTab.id,
            tabId: listTab.id,
            sectionId: nil,
            listRuleId: listTab.list.id,
            sectionRole: .main
        )
    }
}
