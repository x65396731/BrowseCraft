import Foundation
import GRDB

// 中文注释：AppDatabase 持有 SQLite 连接，并直接创建 BrowseCraft 的当前开发期 schema。

/// 中文注释：数据库基础设施只暴露 GRDB 队列给基础设施层仓储使用。
/// 中文注释：发布前允许删除 App 重建数据库，因此当前只创建最终 schema，不兼容旧开发数据库。
final class AppDatabase {
    let queue: DatabaseQueue

    init(path: String? = nil) throws {
        let databasePath: String

        if let path: String = path {
            databasePath = path
        } else {
            databasePath = try Self.defaultDatabasePath()
        }

        self.queue = try DatabaseQueue(path: databasePath)
        try self.queue.write { database in
            try Self.createCurrentSchema(in: database)
            try AppUserRecord.insertLocalDefaultUser(in: database)
            try Self.createCurrentIndexes(in: database)
        }
    }

    private static func defaultDatabasePath() throws -> String {
        let fileManager: FileManager = FileManager.default
        let appSupportDirectory: URL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let browseCraftDirectory: URL = appSupportDirectory.appendingPathComponent(
            "BrowseCraft",
            isDirectory: true
        )

        try fileManager.createDirectory(
            at: browseCraftDirectory,
            withIntermediateDirectories: true
        )

        return browseCraftDirectory.appendingPathComponent("BrowseCraft.sqlite").path
    }

    /// 中文注释：当前开发期只维护一份最终 schema；每张表的字段定义放回各自 Record，避免 AppDatabase 过长。
    private static func createCurrentSchema(in database: Database) throws {
        try AppUserRecord.createTable(in: database)
        try CloudAccountPartitionPreparationRecord.createTable(in: database)
        try SourceRecord.createTable(in: database)
        try FavoriteRecord.createTable(in: database)
        try FavoriteItemRecord.createTable(in: database)
        try UserStoreKitTransactionRecord.createTable(in: database)
        try SyncStateRecord.createTable(in: database)
        try SyncQueueRecord.createTable(in: database)
        try CloudRecordMetadataRecord.createTable(in: database)
        try RSSReadingHistoryRecord.createTable(in: database)
        try ComicChapterHistoryRecord.createTable(in: database)
        try UserLibraryStateRecord.createTable(in: database)
        try VideoWatchHistoryRecord.createTable(in: database)
        try TemporaryResourceHistoryRecord.createTable(in: database)
    }

    /// 中文注释：索引创建保持与表创建分离，便于后续按性能热点独立调整。
    private static func createCurrentIndexes(in database: Database) throws {
        try SourceRecord.createIndexes(in: database)
        try FavoriteItemRecord.createIndexes(in: database)
        try RSSReadingHistoryRecord.createIndexes(in: database)
        try ComicChapterHistoryRecord.createIndexes(in: database)
        try VideoWatchHistoryRecord.createIndexes(in: database)
        try UserLibraryStateRecord.createIndexes(in: database)
        try UserStoreKitTransactionRecord.createIndexes(in: database)
        try SyncQueueRecord.createIndexes(in: database)
        try TemporaryResourceHistoryRecord.createIndexes(in: database)
    }
}
