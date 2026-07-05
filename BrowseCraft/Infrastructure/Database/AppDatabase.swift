import Foundation
import GRDB

// 中文注释：AppDatabase 持有 SQLite 连接，并集中注册 BrowseCraft 的数据库迁移。

/// 中文注释：数据库基础设施只暴露 GRDB 队列给基础设施层仓储使用。
/// 中文注释：迁移只负责持久化结构；Repository、UseCase 和 UI 接入在后续小节完成。
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

        migrator.registerMigration("createSourceAndFavoriteTables") { database in
            try database.create(table: SourceRecord.databaseTableName, ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("baseURL", .text).notNull()
                table.column("type", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("configJSON", .text).notNull()
                table.column("enabled", .boolean).notNull().defaults(to: true)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try database.create(table: FavoriteRecord.databaseTableName, ifNotExists: true) { table in
                table.column("itemId", .text).primaryKey()
                table.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("createReadingHistoryTables") { database in
            try database.create(table: AppUserRecord.databaseTableName, ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("displayName", .text)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try database.create(table: RSSReadingHistoryRecord.databaseTableName, ifNotExists: true) { table in
                table.column("userID", .text)
                    .notNull()
                    .references(AppUserRecord.databaseTableName, column: "id", onDelete: .cascade)
                table.column("sourceID", .text).notNull()
                table.column("itemID", .text).notNull()
                table.column("dataType", .text).notNull()
                table.column("title", .text).notNull()
                table.column("dataContent", .text).notNull()
                table.column("dataTime", .datetime).notNull()
                table.column("visitedAt", .datetime).notNull()
                table.column("detailURL", .text)
                table.column("sourceName", .text)
                table.column("originFeedURL", .text)
                table.uniqueKey(["userID", "sourceID", "itemID"])
            }

            try database.create(table: ComicChapterHistoryRecord.databaseTableName, ifNotExists: true) { table in
                table.column("userID", .text)
                    .notNull()
                    .references(AppUserRecord.databaseTableName, column: "id", onDelete: .cascade)
                table.column("sourceID", .text).notNull()
                table.column("comicItemID", .text).notNull()
                table.column("comicTitle", .text).notNull()
                table.column("chapterID", .text)
                table.column("chapterKey", .text).notNull()
                table.column("chapterURL", .text)
                table.column("chapterTitle", .text).notNull()
                table.column("visitedAt", .datetime).notNull()
                table.column("coverURL", .text)
                table.column("lastReaderPageURL", .text)
                table.column("lastPageImageURL", .text)
                table.column("lastPageImageCacheKey", .text)
                table.column("lastPageIndex", .integer)
                table.column("previousChapterURL", .text)
                table.column("nextChapterURL", .text)
                table.uniqueKey(["userID", "sourceID", "comicItemID", "chapterKey"])
            }

            try Self.insertLocalDefaultUser(in: database)
            try Self.createReadingHistoryIndexes(in: database)
        }

        migrator.registerMigration("addComicHistoryLastReaderPageURL") { database in
            if try Self.table(
                ComicChapterHistoryRecord.databaseTableName,
                hasColumn: "lastReaderPageURL",
                in: database
            ) == false {
                try database.alter(table: ComicChapterHistoryRecord.databaseTableName) { table in
                    table.add(column: "lastReaderPageURL", .text)
                }
            }
        }

        migrator.registerMigration("addComicHistoryChapterNavigationURLs") { database in
            if try Self.table(
                ComicChapterHistoryRecord.databaseTableName,
                hasColumn: "previousChapterURL",
                in: database
            ) == false {
                try database.alter(table: ComicChapterHistoryRecord.databaseTableName) { table in
                    table.add(column: "previousChapterURL", .text)
                }
            }

            if try Self.table(
                ComicChapterHistoryRecord.databaseTableName,
                hasColumn: "nextChapterURL",
                in: database
            ) == false {
                try database.alter(table: ComicChapterHistoryRecord.databaseTableName) { table in
                    table.add(column: "nextChapterURL", .text)
                }
            }
        }

        migrator.registerMigration("createUserLibraryStateTable") { database in
            try database.create(table: UserLibraryStateRecord.databaseTableName, ifNotExists: true) { table in
                table.column("userID", .text)
                    .primaryKey()
                    .references(AppUserRecord.databaseTableName, column: "id", onDelete: .cascade)
                table.column("selectedSourceID", .text).notNull()
                table.column("listContextJSON", .text)
                table.column("lastRefreshAt", .datetime)
                table.column("updatedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("createVideoWatchHistoryTable") { database in
            try database.create(table: VideoWatchHistoryRecord.databaseTableName, ifNotExists: true) { table in
                table.column("userID", .text)
                    .notNull()
                    .references(AppUserRecord.databaseTableName, column: "id", onDelete: .cascade)
                table.column("sourceID", .text).notNull()
                table.column("vodID", .text).notNull()
                table.column("videoTitle", .text).notNull()
                table.column("episodeTitle", .text)
                table.column("episodeKey", .text).notNull()
                table.column("sourceIndex", .integer).notNull()
                table.column("episodeIndex", .integer).notNull()
                table.column("detailURL", .text)
                table.column("playPageURL", .text).notNull()
                table.column("candidateMediaURL", .text)
                table.column("candidateMediaKind", .text).notNull()
                table.column("playbackRequestConfigJSON", .text)
                table.column("coverURL", .text)
                table.column("sourceName", .text)
                table.column("lastPlaybackTime", .real).notNull().defaults(to: 0)
                table.column("duration", .real)
                table.column("visitedAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.column("previousEpisodeURL", .text)
                table.column("nextEpisodeURL", .text)
                table.uniqueKey(["userID", "sourceID", "vodID", "sourceIndex", "episodeIndex"])
            }

            try database.execute(
                sql: """
                CREATE INDEX IF NOT EXISTS idx_video_watch_history_user_updated_at
                ON \(VideoWatchHistoryRecord.databaseTableName)(userID, updatedAt DESC)
                """
            )
        }

        return migrator
    }

    private static func insertLocalDefaultUser(in database: Database) throws {
        let now: Date = Date()

        try database.execute(
            sql: """
            INSERT OR IGNORE INTO \(AppUserRecord.databaseTableName)
                (id, displayName, createdAt, updatedAt)
            VALUES (?, ?, ?, ?)
            """,
            arguments: [
                AppUser.localDefaultID,
                "Local Default",
                now,
                now
            ]
        )
    }

    private static func createReadingHistoryIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_rss_reading_history_user_visited_at
            ON \(RSSReadingHistoryRecord.databaseTableName)(userID, visitedAt DESC)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_comic_chapter_history_user_visited_at
            ON \(ComicChapterHistoryRecord.databaseTableName)(userID, visitedAt DESC)
            """
        )
    }

    private static func table(_ tableName: String, hasColumn columnName: String, in database: Database) throws -> Bool {
        let rows: [Row] = try Row.fetchAll(database, sql: "PRAGMA table_info(\(tableName))")
        return rows.contains { row in
            let name: String = row["name"]
            return name == columnName
        }
    }
}
