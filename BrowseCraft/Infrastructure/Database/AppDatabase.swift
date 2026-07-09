import Foundation
import GRDB

// 中文注释：AppDatabase 持有 SQLite 连接，并集中注册 BrowseCraft 的当前开发期 schema。

/// 中文注释：数据库基础设施只暴露 GRDB 队列给基础设施层仓储使用。
/// 中文注释：当前仍处于开发阶段，schema 以当前最终形态为准，不维护生产式增量迁移兼容。
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

        migrator.registerMigration("createCurrentSchema") { database in
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
                table.column("userID", .text)
                    .primaryKey()
                    .references(AppUserRecord.databaseTableName, column: "id", onDelete: .cascade)
                table.column("favoriteItemIDsJSON", .text).notNull()
                table.column("favoriteItemsJSON", .text).notNull()
                table.column("rssFavoritesJSON", .text)
                table.column("comicFavoritesJSON", .text)
                table.column("videoFavoritesJSON", .text)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try database.create(table: AppUserRecord.databaseTableName, ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("displayName", .text)
                table.column("hasRemovedAds", .boolean).notNull().defaults(to: false)
                table.column("pendingAdPoints", .integer).notNull().defaults(to: 0)
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

            try database.create(table: UserLibraryStateRecord.databaseTableName, ifNotExists: true) { table in
                table.column("userID", .text)
                    .primaryKey()
                    .references(AppUserRecord.databaseTableName, column: "id", onDelete: .cascade)
                table.column("selectedSourceID", .text)
                table.column("listContextJSON", .text)
                table.column("lastRefreshAt", .datetime)
                table.column("updatedAt", .datetime).notNull()
            }

            try database.create(table: VideoWatchHistoryRecord.databaseTableName, ifNotExists: true) { table in
                table.column("userID", .text)
                    .notNull()
                    .references(AppUserRecord.databaseTableName, column: "id", onDelete: .cascade)
                table.column("sourceID", .text).notNull()
                table.column("vodID", .text).notNull()
                table.column("workKey", .text).notNull()
                table.column("videoTitle", .text).notNull()
                table.column("episodeTitle", .text)
                table.column("episodeKey", .text).notNull()
                table.column("sourceIndex", .integer).notNull()
                table.column("episodeIndex", .integer).notNull()
                table.column("detailURL", .text)
                table.column("playPageURL", .text).notNull()
                table.column("candidateMediaURL", .text)
                table.column("candidateMediaKind", .text).notNull()
                table.column("playbackStatusJSON", .text)
                table.column("playbackRequestConfigJSON", .text)
                table.column("coverURL", .text)
                table.column("sourceName", .text)
                table.column("lastPlaybackTime", .real).notNull().defaults(to: 0)
                table.column("duration", .real)
                table.column("visitedAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.column("previousEpisodeURL", .text)
                table.column("nextEpisodeURL", .text)
                table.uniqueKey(["userID", "sourceID", "workKey"])
            }

            try Self.createTemporaryResourceHistoryTable(in: database)

            try Self.insertLocalDefaultUser(in: database)
            try Self.createIndexes(in: database)
        }

        migrator.registerMigration("createTemporaryResourceHistory") { database in
            try Self.createTemporaryResourceHistoryTable(in: database)
            try Self.createTemporaryResourceHistoryIndexes(in: database)
        }

        return migrator
    }

    private static func createTemporaryResourceHistoryTable(in database: Database) throws {
        try database.create(table: TemporaryResourceHistoryRecord.databaseTableName, ifNotExists: true) { table in
            table.column("userID", .text)
                .notNull()
                .references(AppUserRecord.databaseTableName, column: "id", onDelete: .cascade)
            table.column("kind", .text).notNull()
            table.column("title", .text).notNull()
            table.column("resourceURL", .text).notNull()
            table.column("coverURL", .text)
            table.column("sourcePageURL", .text)
            table.column("matchedKeyword", .text)
            table.column("videoPlaybackKind", .text)
            table.column("visitedAt", .datetime).notNull()
            table.uniqueKey(["userID", "kind", "resourceURL"])
        }
    }

    private static func insertLocalDefaultUser(in database: Database) throws {
        let now: Date = Date()

        try database.execute(
            sql: """
            INSERT OR IGNORE INTO \(AppUserRecord.databaseTableName)
                (id, displayName, hasRemovedAds, pendingAdPoints, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                AppUser.localDefaultID,
                "Local Default",
                false,
                0,
                now,
                now
            ]
        )
    }


    private static func createIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_sources_updated_at
            ON \(SourceRecord.databaseTableName)(updatedAt DESC)
            """
        )
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
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_video_watch_history_user_updated_at
            ON \(VideoWatchHistoryRecord.databaseTableName)(userID, updatedAt DESC)
            """
        )
        try Self.createTemporaryResourceHistoryIndexes(in: database)
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_video_watch_history_detail_url
            ON \(VideoWatchHistoryRecord.databaseTableName)(userID, sourceID, detailURL)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_video_watch_history_video_title
            ON \(VideoWatchHistoryRecord.databaseTableName)(userID, sourceID, videoTitle)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_rss_reading_history_source
            ON \(RSSReadingHistoryRecord.databaseTableName)(sourceID)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_comic_chapter_history_source
            ON \(ComicChapterHistoryRecord.databaseTableName)(sourceID)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_video_watch_history_source
            ON \(VideoWatchHistoryRecord.databaseTableName)(sourceID)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_user_library_state_selected_source
            ON \(UserLibraryStateRecord.databaseTableName)(selectedSourceID)
            """
        )
    }

    private static func createTemporaryResourceHistoryIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_temporary_resource_history_user_visited_at
            ON \(TemporaryResourceHistoryRecord.databaseTableName)(userID, visitedAt DESC)
            """
        )
    }
}
