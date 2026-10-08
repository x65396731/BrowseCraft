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

    /// 中文注释：整站是否有声——reader 规则全是 `audio` 才算（`docs/design/Library-Book-Page-Redesign-Design.md` 第二节）。
    /// 规则合同允许一个来源同时有 text 与 audio 两种 reader 规则，那种站列表层判不出，按文字书措辞；是不是有声要进详情按章节判。
    func isAudiobookSource(for source: Source) -> Bool {
        guard case .book(let configuration) = source.configuration else {
            return false
        }
        let readers: [BookReaderRule] = configuration.rule.ruleSets.readerRules
        return readers.isEmpty == false && readers.allSatisfy { reader in reader.contentType == .audio }
    }

    func imageRequestConfig(for source: Source, listTab: ListTabRule?) -> RequestConfig? {
        if case .video(let configuration) = source.configuration {
            return self.videoImageRequestConfig(for: configuration, listTab: listTab)
        }

        if case .book(let configuration) = source.configuration {
            return Self.bookImageRequestConfig(for: configuration.rule, listTab: listTab)
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

    /// 中文注释：book 规则此前在这里一律返回 nil（过不了漫画 V2 校验），书架封面请求拿不到来源的
    /// `sharedRequest`——`cookiePolicy` 为空、系统 Cookie 一条不带。2026-10-07 半夏小說：列表经 WebView 过了
    /// Cloudflare、放行 Cookie 已回写系统存储（`BCA-RUNTIME-005` 补充），封面仍 `hasCookie=false`、图床回挑战页。
    /// 与 `BookSourceRuntime` 取列表同一继承：`sharedRequest` → 页 `request` → 列表规则 `request`。
    static func bookImageRequestConfig(for rule: BookSiteRule, listTab: ListTabRule?) -> RequestConfig? {
        let pageID: String? = listTab?.context?.pageId ?? listTab?.id
        let listPages: [BookPageRule] = rule.pages.filter { $0.type == "list" }
        let page: BookPageRule? = listPages.first { pageID != nil && $0.id == pageID } ?? listPages.first
        let listRule: BookListRule? = page?.ruleRefs.list.flatMap { listRuleID in
            rule.ruleSets.listRules.first { $0.id == listRuleID }
        }
        return RequestConfigResolver().resolve(rule.sharedRequest, page?.request, listRule?.request)
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
