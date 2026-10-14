import Foundation
import GRDB
import Testing
@testable import BrowseCraft

/// docs/design/Account-Deletion-Design.md 第五节第 6 步：删一个 UUID 的本机数据，不碰别的账号。
/// 不按表名逐一写数据：从 schema 里找出全部带 userID 列的表，每张给两个账号各塞一行——以后新加的表也会被这里覆盖到。
struct GRDBAccountDeletionLocalDataStoreTests {
    private static let deletedScope: String = "cloud:deleted"
    private static let keptScope: String = "cloud:kept"

    @Test func deletesEveryUserScopedRowAndSyncStateOnlyForTheDeletedAccount() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let deletedUserID: UUID = UUID()
        let keptUserID: UUID = UUID()
        let userTables: [String] = try Self.seed(
            database: database,
            deletedUserID: deletedUserID,
            keptUserID: keptUserID
        )
        #expect(userTables.contains("sources"))
        #expect(userTables.contains("local_books"))
        #expect(userTables.contains("cloud_app_user_association_attestations"))

        let store: GRDBAccountDeletionLocalDataStore = GRDBAccountDeletionLocalDataStore(database: database)
        #expect(try store.associatedCloudScopes(for: deletedUserID) == [CloudAccountScope(rawValue: Self.deletedScope)])

        let filePaths: [String] = try store.deleteLocalData(for: deletedUserID)

        #expect(Set(filePaths) == ["deleted.epub", "deleted.cover"])
        try database.queue.read { database in
            for table: String in userTables {
                let deletedCount: Int = try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM \(table) WHERE userID = ?",
                    arguments: [deletedUserID.uuidString]
                ) ?? -1
                let keptCount: Int = try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM \(table) WHERE userID = ?",
                    arguments: [keptUserID.uuidString]
                ) ?? -1
                #expect(deletedCount == 0, "\(table) 还留着被删账号的行")
                #expect(keptCount == 1, "\(table) 误删了别的账号的行")
            }
            for table: String in ["sync_state", "cloud_record_metadata", "sync_queue"] {
                let deletedScopeCount: Int = try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM \(table) WHERE accountScope = ?",
                    arguments: [Self.deletedScope]
                ) ?? -1
                let keptScopeCount: Int = try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM \(table) WHERE accountScope = ?",
                    arguments: [Self.keptScope]
                ) ?? -1
                #expect(deletedScopeCount == 0, "\(table) 还留着被删账号分区的同步状态")
                #expect(keptScopeCount == 1, "\(table) 误删了别的分区")
            }
            let users: [String] = try String.fetchAll(database, sql: "SELECT id FROM users")
            #expect(users == [keptUserID.uuidString])
            #expect(try Row.fetchAll(database, sql: "PRAGMA foreign_key_check").isEmpty)
        }
    }

    @Test func deletingUnknownUserIsANoOp() throws {
        let database: AppDatabase = try Self.makeDatabase()
        let store: GRDBAccountDeletionLocalDataStore = GRDBAccountDeletionLocalDataStore(database: database)

        #expect(try store.deleteLocalData(for: UUID()).isEmpty)
    }

    // MARK: - 造数据

    private static func makeDatabase() throws -> AppDatabase {
        let path: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountDeletionLocalData-\(UUID().uuidString).sqlite")
            .path
        return try AppDatabase(path: path)
    }

    /// 返回带 userID 列的全部表名（不含 users 自己）。
    private static func seed(
        database: AppDatabase,
        deletedUserID: UUID,
        keptUserID: UUID
    ) throws -> [String] {
        return try database.queue.write { database in
            try AppUserRecord.insertUser(id: deletedUserID.uuidString, in: database)
            try AppUserRecord.insertUser(id: keptUserID.uuidString, in: database)

            let tables: [String] = try String.fetchAll(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'"
            )
            var userTables: [String] = []
            for table: String in tables.sorted() where table != "users" {
                let columns: [Row] = try Row.fetchAll(database, sql: "PRAGMA table_info(\(table))")
                let names: [String] = columns.map { $0["name"] }
                if names.contains("userID") {
                    userTables.append(table)
                    for (userID, label, scope) in [
                        (deletedUserID, "deleted", Self.deletedScope),
                        (keptUserID, "kept", Self.keptScope)
                    ] {
                        var overrides: [String: (any DatabaseValueConvertible)?] = ["userID": userID.uuidString]
                        if table == "local_books" {
                            overrides["fileRelativePath"] = "\(label).epub"
                            overrides["coverRelativePath"] = "\(label).cover"
                        }
                        if names.contains("accountScope") {
                            overrides["accountScope"] = scope
                        }
                        try Self.insertRow(into: table, columns: columns, overrides: overrides, in: database)
                    }
                } else if names.contains("accountScope") {
                    for scope: String in [Self.deletedScope, Self.keptScope] {
                        try Self.insertRow(
                            into: table,
                            columns: columns,
                            overrides: ["accountScope": scope],
                            in: database
                        )
                    }
                }
            }
            return userTables
        }
    }

    /// 非空或主键、且无默认值的列按声明类型填占位值；其余列留空。
    private static func insertRow(
        into table: String,
        columns: [Row],
        overrides: [String: (any DatabaseValueConvertible)?],
        in database: Database
    ) throws {
        var names: [String] = []
        var values: [(any DatabaseValueConvertible)?] = []
        for column: Row in columns {
            let name: String = column["name"]
            let type: String = (column["type"] as String? ?? "").uppercased()
            let notNull: Bool = column["notnull"]
            let hasDefault: Bool = (column["dflt_value"] as DatabaseValue).isNull == false
            // 中文注释：SQLite 的 TEXT 主键不隐含 NOT NULL，也要填。
            let isPrimaryKey: Bool = (column["pk"] as Int) > 0
            if let override = overrides[name] {
                names.append(name)
                values.append(override)
            } else if (notNull || isPrimaryKey) && hasDefault == false {
                names.append(name)
                if type.contains("INT") || type.contains("BOOL") {
                    values.append(0)
                } else if type.contains("REAL") || type.contains("DOUBLE") {
                    values.append(0.0)
                } else if type.contains("BLOB") {
                    values.append(Data([0]))
                } else if type.contains("DATE") {
                    values.append(Date(timeIntervalSince1970: 1_785_000_000))
                } else {
                    values.append("\(name)-\(UUID().uuidString)")
                }
            }
        }
        let placeholders: String = Array(repeating: "?", count: names.count).joined(separator: ", ")
        try database.execute(
            sql: "INSERT INTO \(table) (\(names.joined(separator: ", "))) VALUES (\(placeholders))",
            arguments: StatementArguments(values)
        )
    }
}
