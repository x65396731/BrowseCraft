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
        Self.localBooksIdentifier,
        Self.bookProgressDetachedIdentifier,
        Self.bookReadingHistoryIdentifier,
        Self.removeRSSIdentifier
    ]

    /// 中文注释：v2——sources 增加 `origin` 列，记「来自个人生成」等出身，本地副本才能随服务器裁决清理。
    static let sourcesAddOriginIdentifier: String = "v2.sources-add-origin"

    /// 中文注释：v3——本地书三张表（书、续读位置、书签），见 docs/design/Local-Book-Import-Design.md。
    /// 本地书不是 Source，也不进 CloudKit；位置字段是 Readium Locator 的 JSON。
    static let localBooksIdentifier: String = "v3.local-books"

    /// 中文注释：v4——续读位置与书签不再外键到 local_books：站点书（规则来源里的作品）没有 local_books 行，
    /// 作品标识改为「本地 UUID 或 sourceID + 作品地址派生的 UUID」（设计第六节第 3 条）。SQLite 去外键只能重建表。
    static let bookProgressDetachedIdentifier: String = "v4.book-progress-detached-from-local-books"

    /// 中文注释：v5——站点书阅读历史，一本书一条；History 页与漫画、视频同列（docs/design/Book-Kind-Wiring-Design.md 第二十三节）。
    /// 续读位置仍在 book_reading_progress，这张表只记书名、封面、最后读到的章节与访问时间。
    static let bookReadingHistoryIdentifier: String = "v5.book-reading-history"

    /// 中文注释：v6——RSS 整体下线（2026-09-16，用户裁决「App 全删，服务器也下线」）。App 已不认 rss 来源、rss 历史与 rss 收藏：
    /// 来源表里任何一行解码失败都会让整张来源列表读取抛错，所以必须在迁移里清掉，不能留给运行时。
    /// 书籍收藏此前被记成 rss（条目形态是 article），属于书籍来源的改记 book 保留，其余 rss 收藏删除。
    /// 不给云端排删除：旧版设备上的 RSS 数据不动；新版下行时按 kind 跳过（SourceCloudPayload / FavoriteItemSyncService）。
    /// favorites 聚合表的 rssFavoritesJSON 列从未写入过值，留作死列，不为它重建表。
    static let removeRSSIdentifier: String = "v6.remove-rss"

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

        migrator.registerMigration(Self.bookProgressDetachedIdentifier) { database in
            try database.create(table: "book_reading_progress_v4") { table in
                table.column("bookID", .text).notNull()
                table.column("userID", .text)
                    .notNull()
                    .references("users", column: "id", onDelete: .cascade)
                table.column("locatorJSON", .text).notNull()
                table.column("totalProgression", .double)
                table.column("updatedAt", .datetime).notNull()
                table.primaryKey(["bookID", "userID"])
            }
            try database.execute(
                sql: """
                INSERT INTO book_reading_progress_v4 (bookID, userID, locatorJSON, totalProgression, updatedAt)
                SELECT bookID, userID, locatorJSON, totalProgression, updatedAt FROM book_reading_progress
                """
            )
            try database.drop(table: "book_reading_progress")
            try database.rename(table: "book_reading_progress_v4", to: "book_reading_progress")

            try database.create(table: "book_bookmarks_v4") { table in
                table.column("id", .text).primaryKey()
                table.column("bookID", .text).notNull()
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
                INSERT INTO book_bookmarks_v4 (id, bookID, userID, locatorJSON, title, snippet, createdAt)
                SELECT id, bookID, userID, locatorJSON, title, snippet, createdAt FROM book_bookmarks
                """
            )
            try database.drop(table: "book_bookmarks")
            try database.rename(table: "book_bookmarks_v4", to: "book_bookmarks")
            try database.execute(
                sql: """
                CREATE INDEX idx_book_bookmarks_book_created_at
                ON book_bookmarks(bookID, createdAt DESC)
                """
            )
        }

        migrator.registerMigration(Self.bookReadingHistoryIdentifier) { database in
            try database.create(table: "book_reading_history") { table in
                table.column("userID", .text)
                    .notNull()
                    .references("users", column: "id", onDelete: .cascade)
                table.column("sourceID", .text).notNull()
                table.column("detailURL", .text).notNull()
                table.column("bookItemID", .text).notNull()
                table.column("bookTitle", .text).notNull()
                table.column("coverURL", .text)
                table.column("chapterTitle", .text)
                table.column("chapterURL", .text)
                table.column("visitedAt", .datetime).notNull()
                table.column("sourceSnapshotJSON", .text)
                table.primaryKey(["userID", "sourceID", "detailURL"])
            }
            try database.execute(
                sql: """
                CREATE INDEX idx_book_reading_history_user_visited_at
                ON book_reading_history(userID, visitedAt DESC)
                """
            )
        }

        migrator.registerMigration(Self.removeRSSIdentifier) { database in
            try database.execute(
                sql: """
                DELETE FROM sync_queue
                WHERE entityType = 'source'
                  AND entityID IN (SELECT id FROM sources WHERE kind = 'rss')
                """
            )
            try database.execute(
                sql: """
                UPDATE favorite_items
                SET kind = 'book',
                    itemJSON = replace(itemJSON, '"kind":"rss"', '"kind":"book"')
                WHERE kind = 'rss'
                  AND EXISTS (
                    SELECT 1 FROM sources
                    WHERE sources.userID = favorite_items.userID
                      AND sources.id = favorite_items.sourceID
                      AND sources.kind = 'book'
                  )
                """
            )
            // 中文注释：收藏的同步实体 id 是「sourceID 的 UTF-8 字节数:sourceID + itemID」（FavoriteItemIdentity.syncEntityID）。
            try database.execute(
                sql: """
                DELETE FROM sync_queue
                WHERE entityType = 'favoriteItem'
                  AND entityID IN (
                    SELECT length(CAST(sourceID AS BLOB)) || ':' || sourceID || itemID
                    FROM favorite_items WHERE kind = 'rss'
                  )
                """
            )
            try database.execute(sql: "DELETE FROM favorite_items WHERE kind = 'rss'")
            try database.execute(sql: "DELETE FROM sources WHERE kind = 'rss'")
            try database.drop(table: "rss_reading_history")
            let favoriteUserIDs: [String] = try String.fetchAll(database, sql: "SELECT userID FROM favorites")
            for userID: String in favoriteUserIDs {
                try FavoriteAggregateBuilder.rebuild(userID: userID, in: database)
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
