import Foundation
import GRDB

// 中文注释：AppDatabase.swift 属于应用源码，用于说明本文件承载的核心职责。

/// 中文注释：持有 SQLite 连接并负责数据库迁移。
/// 中文注释：它直接依赖 GRDB，其他层应该通过仓储协议访问数据。
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

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator: DatabaseMigrator = DatabaseMigrator()

        migrator.registerMigration("createBrowseCraftCore") { database in
            try database.create(table: SourceRecord.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("baseURL", .text).notNull()
                table.column("type", .text).notNull()
                table.column("ruleJSON", .text).notNull()
                table.column("enabled", .boolean).notNull().defaults(to: true)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try database.create(table: ContentItemRecord.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("sourceId", .text)
                    .notNull()
                    .indexed()
                    .references(SourceRecord.databaseTableName, onDelete: .cascade)
                table.column("title", .text).notNull()
                table.column("detailURL", .text).notNull()
                table.column("coverURL", .text)
                table.column("type", .text).notNull()
                table.column("latestText", .text)
                table.column("updatedAt", .datetime)
            }

            try database.create(table: FavoriteRecord.databaseTableName) { table in
                table.column("itemId", .text)
                    .primaryKey()
                    .references(ContentItemRecord.databaseTableName, onDelete: .cascade)
                table.column("createdAt", .datetime).notNull()
            }

            try database.create(table: ReadingHistoryRecord.databaseTableName) { table in
                table.column("itemId", .text)
                    .primaryKey()
                    .references(ContentItemRecord.databaseTableName, onDelete: .cascade)
                table.column("chapterId", .text)
                table.column("pageIndex", .integer).notNull().defaults(to: 0)
                table.column("updatedAt", .datetime).notNull()
            }
        }

        return migrator
    }
}

