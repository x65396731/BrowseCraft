import Foundation
import GRDB

// 中文注释：AppDatabase 持有 SQLite 连接，并通过版本化迁移维护 BrowseCraft schema。

/// 中文注释：数据库基础设施只暴露 GRDB 队列给基础设施层仓储使用。
/// 中文注释：业务用户由 Keychain 身份 bootstrap 幂等写入；schema 只能通过迁移演进。
final class AppDatabase: @unchecked Sendable {
    static let currentSchemaMigrationIdentifier: String = "v1.initial-schema"
    /// 中文注释：DatabasePool 使用 WAL，让 UI 读取不必等待 Cloud Sync 等后台读取完成。
    let queue: DatabasePool

    init(path: String? = nil) throws {
        let databasePath: String

        if let path: String = path {
            databasePath = path
        } else {
            databasePath = try Self.defaultDatabasePath()
        }

        self.queue = try DatabasePool(path: databasePath)
        try Self.makeMigrator().migrate(self.queue)
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

    /// 中文注释：v1 固化当前 schema。已有同结构开发数据库会由 ifNotExists 安全纳入迁移账本。
    private static func makeMigrator() -> DatabaseMigrator {
        var migrator: DatabaseMigrator = DatabaseMigrator()
        migrator.registerMigration(Self.currentSchemaMigrationIdentifier) { database in
            try Self.createCurrentSchema(in: database)
            try Self.createCurrentIndexes(in: database)
        }
        return migrator
    }

    /// 中文注释：每张表的字段、约束和索引定义继续由对应 Record 持有。
    private static func createCurrentSchema(in database: Database) throws {
        try AppUserRecord.createTable(in: database)
        try CloudAccountPartitionPreparationRecord.createTable(in: database)
        try CloudAppUserAssociationAttestationRecord.createTable(in: database)
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
