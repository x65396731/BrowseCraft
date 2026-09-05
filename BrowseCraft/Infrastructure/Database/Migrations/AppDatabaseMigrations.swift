@preconcurrency import GRDB

// 中文注释：BrowseCraft schema 的唯一演进入口。规则：
// 1. 已注册的迁移永不修改；v1 的建表代码固化在 AppDatabaseSchemaV1。
// 2. 任何 schema 变更都追加一个新的 `registerMigration("vN.描述")`，用 ALTER/CREATE 表达增量。
// 3. Record 的 `Columns` 只描述当前列名，不再拥有建表逻辑。
// 4. 追加迁移后同步更新 AppDatabaseSchemaSnapshotTests 里的快照，让 schema 变更在 review 里显式可见。
enum AppDatabaseMigrations {
    /// 中文注释：按注册顺序列出全部迁移标识；测试用它校验账本，不再各处硬编码。
    static let identifiers: [String] = [
        AppDatabaseSchemaV1.identifier,
        Self.sourcesAddOriginIdentifier
    ]

    /// 中文注释：v2——sources 增加 `origin` 列，记「来自个人生成」等出身，本地副本才能随服务器裁决清理。
    static let sourcesAddOriginIdentifier: String = "v2.sources-add-origin"

    static func makeMigrator() -> DatabaseMigrator {
        var migrator: DatabaseMigrator = DatabaseMigrator()

        migrator.registerMigration(AppDatabaseSchemaV1.identifier) { database in
            try AppDatabaseSchemaV1.apply(to: database)
        }

        migrator.registerMigration(Self.sourcesAddOriginIdentifier) { database in
            try database.alter(table: "sources") { table in
                table.add(column: "origin", .text)
            }
        }

        // 中文注释：下一次 schema 变更从这里开始，例如：
        // migrator.registerMigration("v2.sources-add-sort-order") { database in
        //     try database.alter(table: "sources") { table in
        //         table.add(column: "sortOrder", .integer).notNull().defaults(to: 0)
        //     }
        // }

        return migrator
    }
}
