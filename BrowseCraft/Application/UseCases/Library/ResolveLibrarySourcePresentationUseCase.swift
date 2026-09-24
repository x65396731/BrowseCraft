import BrowseCraftCore
import BrowseCraftDomain
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

        if case .book(let configuration) = source.configuration {
            return self.bookListTabs(for: configuration)
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

        guard let resolvedRule: ResolvedComicSiteRuleV2 = ComicSiteRuleV2Validator()
            .validate(rule: rule)
            .resolvedRule else {
            return nil
        }
        let context: ListContext? = listTab?.context
        let entry: ResolvedComicListEntry? = resolvedRule.listEntries.first { entry in
            if let ruleID: String = context?.listRuleId {
                return entry.ruleID == ruleID
            }
            if let tabID: String = context?.tabId ?? listTab?.id {
                return entry.entryID == tabID
            }
            if let pageID: String = context?.pageId {
                return entry.pageID == pageID
            }
            return false
        } ?? resolvedRule.primaryListEntry
        return entry?.effectiveRequest
    }

    private func videoImageRequestConfig(
        for configuration: VideoSourceConfiguration,
        listTab: ListTabRule?
    ) -> RequestConfig? {
        guard let resolvedRule: ResolvedVideoSiteRule = try? ResolvedVideoSiteRule(
            validating: configuration.rule
        ) else {
            return nil
        }
        let pageID: String? = listTab?.context?.pageId
        let entry: ResolvedVideoListEntry? = resolvedRule.listEntries.first { entry in
            return pageID == nil || entry.pageID == pageID
        }
        return entry?.effectiveRequest
    }

    private func videoListTabs(for configuration: VideoSourceConfiguration) -> [ListTabRule] {
        return configuration.rule.pages.map { page in
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

    /// 中文注释：book 规则是独立的 BookSiteRule，不走 SiteRule.availableListTabs——此前这里一律返回空，
    /// 引擎推导出的多个列表页（BC-PAGE-063）在书架上看不到。每个 `type="list"` 页一个标签，搜索页不算；
    /// 选中后 `pageId` 经 SourceRuntimeContext.pageID 交给 BookSourceRuntime 按页取列表。
    private func bookListTabs(for configuration: BookSourceConfiguration) -> [ListTabRule] {
        return configuration.rule.pages.compactMap { page in
            guard page.type == "list",
                  let listRuleID: String = page.ruleRefs.list,
                  let pageURL: String = page.url else {
                return nil
            }
            return ListTabRule(
                id: page.id,
                title: page.title ?? page.id,
                list: ListRule(
                    id: listRuleID,
                    url: pageURL,
                    item: "",
                    title: "",
                    link: "",
                    type: .article
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

    func shouldOpenReaderDirectly(for source: Source) -> Bool {
        guard let rule: SiteRule = source.ruleConfiguration?.rule else {
            return false
        }

        guard let resolvedRule: ResolvedComicSiteRuleV2 = ComicSiteRuleV2Validator()
            .validate(rule: rule)
            .resolvedRule,
              let entry: ResolvedComicDetailEntry = resolvedRule.primaryDetailEntry else {
            return false
        }
        return resolvedRule.detailRule(for: entry).treatDetailURLAsChapter
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
