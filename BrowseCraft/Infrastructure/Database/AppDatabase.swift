import Foundation
import GRDB

// 中文注释：AppDatabase 持有 SQLite 连接，并通过版本化迁移维护 BrowseCraft schema。

/// 中文注释：数据库基础设施只暴露 GRDB 队列给基础设施层仓储使用。
/// 中文注释：业务用户由 Keychain 身份 bootstrap 幂等写入；schema 只能通过 AppDatabaseMigrations 追加迁移演进。
final class AppDatabase: @unchecked Sendable {
    /// 中文注释：最新一次迁移的标识；schema 只能通过 AppDatabaseMigrations 追加迁移演进。
    static var currentSchemaMigrationIdentifier: String {
        return AppDatabaseMigrations.identifiers.last ?? ""
    }
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

    /// 中文注释：迁移账本由 AppDatabaseMigrations 维护；这里只负责套用。
    private static func makeMigrator() -> DatabaseMigrator {
        return AppDatabaseMigrations.makeMigrator()
    }
}
