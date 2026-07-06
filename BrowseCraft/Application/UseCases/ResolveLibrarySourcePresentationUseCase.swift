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
        guard let rule: SiteRule = source.ruleConfiguration?.rule else {
            return nil
        }

        return rule.request(for: listTab)
    }

    private func videoListTabs(for configuration: VideoSourceConfiguration) -> [ListTabRule] {
        guard configuration.definition.siteKind == .macCMS else {
            return []
        }

        return [
            self.videoListTab(id: "video.home", title: "首页", listURL: configuration.definition.entryURL.absoluteString),
            self.videoListTab(id: "video.category.1", title: "电影", listURL: "/vodtype/1.html"),
            self.videoListTab(id: "video.category.2", title: "电视剧", listURL: "/vodtype/2.html"),
            self.videoListTab(id: "video.category.3", title: "综艺", listURL: "/vodtype/3.html"),
            self.videoListTab(id: "video.category.4", title: "动漫", listURL: "/vodtype/4.html")
        ]
    }

    private func videoListTab(id: String, title: String, listURL: String) -> ListTabRule {
        return ListTabRule(
            id: id,
            title: title,
            list: ListRule(
                id: id,
                url: listURL,
                item: ".ewave-vodlist__box",
                title: ".ewave-vodlist__thumb@title",
                link: "a[href*=/voddetail/]@href",
                cover: ".ewave-vodlist__thumb@data-original",
                type: .video,
                latestText: ".pic-text.text-right"
            ),
            context: ListContext(
                pageId: "video",
                tabId: id,
                sectionId: nil,
                listRuleId: id,
                sectionRole: .main
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
