import Foundation
import GRDB

// 中文注释：FavoriteRecord.swift 属于数据库记录映射层，用于说明本文件承载的核心职责。

/// 中文注释：FavoriteRecord 是 struct，负责本模块中的对应职责。
struct FavoriteRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "favorites"

    var itemId: String
    var createdAt: Date
}

