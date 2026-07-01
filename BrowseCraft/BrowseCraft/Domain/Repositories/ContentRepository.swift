import Foundation

// 中文注释：ContentRepository.swift 属于仓储协议层，用于说明本文件承载的核心职责。

/// 中文注释：面向领域层的内容条目仓储协议，负责解析后条目的读取和保存。
protocol ContentRepository {
    /// 中文注释：fetchItems 方法封装当前类型的一段业务或界面行为。
    func fetchItems() throws -> [ContentItem]
    /// 中文注释：fetchItems 方法封装当前类型的一段业务或界面行为。
    func fetchItems(sourceId: String?) throws -> [ContentItem]
    /// 中文注释：saveItems 方法封装当前类型的一段业务或界面行为。
    func saveItems(_ items: [ContentItem]) throws
}

