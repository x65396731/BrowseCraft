import Foundation

// 中文注释：ContentItem.swift 属于领域模型层，用于说明本文件承载的核心职责。

/// 中文注释：BrowseCraft 在 Library 中展示的标准化内容条目。
/// 中文注释：原始来源可以是网页、RSS、JSON 或 XML，解析后 UI 只需要这个统一模型。
struct ContentItem: Identifiable, Hashable {
    var id: String
    var sourceId: String
    var title: String
    var detailURL: String
    var coverURL: String?
    var type: ContentType
    var latestText: String?
    var updatedAt: Date?
    /// 中文注释：记录当前列表快照内的展示顺序，缓存读取时用它恢复规则解析出的网页顺序。
    var listOrder: Int? = nil
    /// 中文注释：记录列表项来自哪个页面、Tab 或 Section，后续详情/阅读页可用它缩小解析范围。
    var listContext: ListContext? = nil
}
