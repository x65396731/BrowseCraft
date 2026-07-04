import Foundation

// 中文注释：LoadLibraryUseCase.swift 属于应用用例层，用于说明本文件承载的核心职责。

/// 中文注释：加载 Library 页面需要展示的内容条目。
struct LoadLibraryUseCase {
    private let contentRepository: ContentRepository

    init(contentRepository: ContentRepository) {
        self.contentRepository = contentRepository
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute(sourceId: String? = nil) throws -> [ContentItem] {
        return try self.contentRepository.fetchItems(sourceId: sourceId)
    }

    /// 中文注释：Library 的可见缓存以当前 tab/listRule 为边界，避免同一 source 的其它 tab 条目混入。
    func execute(sourceId: String?, listTab: ListTabRule?) throws -> [ContentItem] {
        return try self.execute(
            sourceId: sourceId,
            context: self.listContext(listTab: listTab)
        )
    }

    /// 中文注释：Runtime-first 入口；调用方可直接用 ListContext 读取当前列表缓存。
    func execute(sourceId: String?, context: ListContext?) throws -> [ContentItem] {
        return try self.contentRepository.fetchItems(
            sourceId: sourceId,
            context: context
        )
    }

    private func listContext(listTab: ListTabRule?) -> ListContext? {
        guard let listTab: ListTabRule = listTab else {
            return nil
        }

        if var context: ListContext = listTab.context {
            if context.listRuleId == nil {
                context.listRuleId = listTab.list.id
            }

            return context
        }

        // 中文注释：旧规则没有 PageRule 上下文时，tab id 与 listRule id 仍可作为缓存隔离键。
        return ListContext(
            pageId: listTab.id,
            tabId: listTab.id,
            sectionId: nil,
            listRuleId: listTab.list.id,
            sectionRole: .main
        )
    }
}

struct ResolveLibrarySourcePresentationUseCase {
    func listTabs(for source: Source?) -> [ListTabRule] {
        guard let rule: SiteRule = source?.ruleConfiguration?.rule else {
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
