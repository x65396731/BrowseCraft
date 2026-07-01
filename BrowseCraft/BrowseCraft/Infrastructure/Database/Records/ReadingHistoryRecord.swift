import Foundation
import GRDB

// 中文注释：ReadingHistoryRecord.swift 属于数据库记录映射层，用于说明本文件承载的核心职责。

/// 中文注释：ReadingHistoryRecord 是 struct，负责本模块中的对应职责。
struct ReadingHistoryRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "readingHistory"

    var itemId: String
    var chapterId: String?
    var pageIndex: Int
    var updatedAt: Date

    init(history: ReadingHistory) {
        self.itemId = history.itemId
        self.chapterId = history.chapterId
        self.pageIndex = history.pageIndex
        self.updatedAt = history.updatedAt
    }

    /// 中文注释：domainModel 方法封装当前类型的一段业务或界面行为。
    func domainModel() -> ReadingHistory {
        return ReadingHistory(
            itemId: self.itemId,
            chapterId: self.chapterId,
            pageIndex: self.pageIndex,
            updatedAt: self.updatedAt
        )
    }
}

