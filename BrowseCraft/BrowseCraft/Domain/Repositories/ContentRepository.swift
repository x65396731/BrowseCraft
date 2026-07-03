import Foundation

// 中文注释：ContentRepository.swift 属于仓储协议层，用于说明本文件承载的核心职责。

/// 中文注释：面向领域层的内容条目仓储协议，负责解析后条目的读取和保存。
protocol ContentRepository {
    /// 中文注释：fetchItems 方法封装当前类型的一段业务或界面行为。
    func fetchItems() throws -> [ContentItem]
    /// 中文注释：fetchItems 方法封装当前类型的一段业务或界面行为。
    func fetchItems(sourceId: String?) throws -> [ContentItem]
    /// 中文注释：按列表上下文读取缓存，避免同一 source 的不同 tab/规则结果互相混入。
    func fetchItems(sourceId: String?, context: ListContext?) throws -> [ContentItem]
    /// 中文注释：saveItems 方法封装当前类型的一段业务或界面行为。
    func saveItems(_ items: [ContentItem]) throws
    /// 中文注释：刷新列表时用新结果替换同一 source/tab/listRule 的旧缓存，避免规则更新后残留旧条目。
    func replaceItems(_ items: [ContentItem], sourceId: String, context: ListContext?) throws
}

extension ContentRepository {
    func fetchItems(sourceId: String?, context: ListContext?) throws -> [ContentItem] {
        let items: [ContentItem] = try self.fetchItems(sourceId: sourceId)

        guard let context: ListContext = context else {
            return items
        }

        return items.filter { item in
            if let tabId: String = context.tabId,
               item.listContext?.tabId != tabId {
                return false
            }

            if let listRuleId: String = context.listRuleId,
               item.listContext?.listRuleId != listRuleId {
                return false
            }

            return true
        }
    }

    func replaceItems(_ items: [ContentItem], sourceId: String, context: ListContext?) throws {
        try self.saveItems(items)
    }
}
