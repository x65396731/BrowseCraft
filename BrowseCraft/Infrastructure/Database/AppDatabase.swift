import BrowseCraftLog
import Foundation
import GRDB

// 中文注释：AppDatabase 持有 SQLite 连接，并通过版本化迁移维护 BrowseCraft schema。

/// 中文注释：数据库基础设施只暴露 GRDB 队列给基础设施层仓储使用。
/// 中文注释：业务用户由 Keychain 身份 bootstrap 幂等写入；schema 只能通过 AppDatabaseMigrations 追加迁移演进。
final class AppDatabase: Sendable {
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

        // 中文注释：数据库的公共钩子（Logging-Design.md `BCA-OBS-014`）：打开与迁移失败记 error，
        // 本次实际执行的迁移逐个记 notice（名字与总耗时），升级后第一次启动的问题因此有据可查。
        let clock: ContinuousClock = ContinuousClock()
        let startedAt: ContinuousClock.Instant = clock.now
        do {
            self.queue = try DatabasePool(path: databasePath)
        } catch {
            AppLog.error(.database, "database-open-failed", ["error": .error(error)])
            throw error
        }
        let migrator: DatabaseMigrator = Self.makeMigrator()
        do {
            let appliedBefore: Set<String> = try self.queue.read { db in
                try migrator.appliedIdentifiers(db)
            }
            try migrator.migrate(self.queue)
            let pending: [String] = AppDatabaseMigrations.identifiers.filter { appliedBefore.contains($0) == false }
            for identifier in pending {
                AppLog.notice(.database, "migration-applied", ["migration": .code(identifier)])
            }
            AppLog.info(.database, "database-opened", [
                "migrationsApplied": .int(pending.count),
                "ms": .duration(clock.now - startedAt)
            ])
        } catch {
            AppLog.error(.database, "migration-failed", ["error": .error(error)])
            throw error
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

    /// 中文注释：迁移账本由 AppDatabaseMigrations 维护；这里只负责套用。
    private static func makeMigrator() -> DatabaseMigrator {
        return AppDatabaseMigrations.makeMigrator()
    }
}
