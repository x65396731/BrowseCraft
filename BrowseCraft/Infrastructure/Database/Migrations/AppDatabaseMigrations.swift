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
        Self.sourcesAddOriginIdentifier,
        Self.localBooksIdentifier
    ]

    /// 中文注释：v2——sources 增加 `origin` 列，记「来自个人生成」等出身，本地副本才能随服务器裁决清理。
    static let sourcesAddOriginIdentifier: String = "v2.sources-add-origin"

    /// 中文注释：v3——本地书三张表（书、续读位置、书签），见 Documentation/Book/Local-Book-Import-Design.md。
    /// 本地书不是 Source，也不进 CloudKit；位置字段是 Readium Locator 的 JSON。
    static let localBooksIdentifier: String = "v3.local-books"

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

        migrator.registerMigration(Self.localBooksIdentifier) { database in
            try database.create(table: "local_books") { table in
                table.column("id", .text).primaryKey()
                table.column("userID", .text)
                    .notNull()
                    .references("users", column: "id", onDelete: .cascade)
                table.column("title", .text).notNull()
                table.column("author", .text)
                table.column("format", .text).notNull()
                table.column("fileRelativePath", .text).notNull()
                table.column("coverRelativePath", .text)
                table.column("fileSHA256", .text).notNull()
                table.column("byteCount", .integer).notNull()
                table.column("importedAt", .datetime).notNull()
                table.column("lastOpenedAt", .datetime)
            }
            try database.execute(
                sql: """
                CREATE INDEX idx_local_books_user_imported_at
                ON local_books(userID, importedAt DESC)
                """
            )
            try database.execute(
                sql: """
                CREATE INDEX idx_local_books_user_sha256
                ON local_books(userID, fileSHA256)
                """
            )

            try database.create(table: "book_reading_progress") { table in
                table.column("bookID", .text)
                    .notNull()
                    .references("local_books", column: "id", onDelete: .cascade)
                table.column("userID", .text)
                    .notNull()
                    .references("users", column: "id", onDelete: .cascade)
                table.column("locatorJSON", .text).notNull()
                table.column("totalProgression", .double)
                table.column("updatedAt", .datetime).notNull()
                table.primaryKey(["bookID", "userID"])
            }

            try database.create(table: "book_bookmarks") { table in
                table.column("id", .text).primaryKey()
                table.column("bookID", .text)
                    .notNull()
                    .references("local_books", column: "id", onDelete: .cascade)
                table.column("userID", .text)
                    .notNull()
                    .references("users", column: "id", onDelete: .cascade)
                table.column("locatorJSON", .text).notNull()
                table.column("title", .text)
                table.column("snippet", .text)
                table.column("createdAt", .datetime).notNull()
            }
            try database.execute(
                sql: """
                CREATE INDEX idx_book_bookmarks_book_created_at
                ON book_bookmarks(bookID, createdAt DESC)
                """
            )
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
