import Foundation
import GRDB

// 中文注释：ContentItemRecord.swift 属于数据库记录映射层，用于说明本文件承载的核心职责。

/// 中文注释：ContentItemRecord 是 struct，负责本模块中的对应职责。
struct ContentItemRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "contentItems"

    var id: String
    var sourceId: String
    var title: String
    var detailURL: String
    var coverURL: String?
    var type: String
    var latestText: String?
    var updatedAt: Date?
    var contextPageId: String?
    var contextTabId: String?
    var contextSectionId: String?
    var contextListRuleId: String?
    var contextSectionRole: String?

    init(item: ContentItem) {
        self.id = item.id
        self.sourceId = item.sourceId
        self.title = item.title
        self.detailURL = item.detailURL
        self.coverURL = item.coverURL
        self.type = item.type.rawValue
        self.latestText = item.latestText
        self.updatedAt = item.updatedAt
        self.contextPageId = item.listContext?.pageId
        self.contextTabId = item.listContext?.tabId
        self.contextSectionId = item.listContext?.sectionId
        self.contextListRuleId = item.listContext?.listRuleId
        self.contextSectionRole = item.listContext?.sectionRole?.rawValue
    }

    /// 中文注释：domainModel 方法封装当前类型的一段业务或界面行为。
    func domainModel() -> ContentItem {
        return ContentItem(
            id: self.id,
            sourceId: self.sourceId,
            title: self.title,
            detailURL: self.detailURL,
            coverURL: self.coverURL,
            type: ContentType(rawValue: self.type) ?? .article,
            latestText: self.latestText,
            updatedAt: self.updatedAt,
            listContext: self.domainListContext()
        )
    }

    private func domainListContext() -> ListContext? {
        if self.contextPageId == nil,
           self.contextTabId == nil,
           self.contextSectionId == nil,
           self.contextListRuleId == nil,
           self.contextSectionRole == nil {
            return nil
        }

        // 中文注释：数据库里保存的是字符串，读取时恢复为领域层 ListContext，未知 role 保持为空以兼容旧数据。
        return ListContext(
            pageId: self.contextPageId,
            tabId: self.contextTabId,
            sectionId: self.contextSectionId,
            listRuleId: self.contextListRuleId,
            sectionRole: self.contextSectionRole.flatMap { role in
                return SectionRole(rawValue: role)
            }
        )
    }
}
