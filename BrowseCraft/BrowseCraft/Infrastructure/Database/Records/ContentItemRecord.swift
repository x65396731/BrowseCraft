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

    init(item: ContentItem) {
        self.id = item.id
        self.sourceId = item.sourceId
        self.title = item.title
        self.detailURL = item.detailURL
        self.coverURL = item.coverURL
        self.type = item.type.rawValue
        self.latestText = item.latestText
        self.updatedAt = item.updatedAt
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
            updatedAt: self.updatedAt
        )
    }
}

