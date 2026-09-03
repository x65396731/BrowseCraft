import Foundation
import GRDB
import Testing
@testable import BrowseCraft

// 中文注释：迁移链跑完之后的 schema 快照。任何 schema 变更都必须同时做两件事：
// 在 AppDatabaseMigrations 追加一个新迁移，并把这里的快照更新成新的 dump。
// 直接改 AppDatabaseSchemaV1 或只改 Record 而不加迁移，这个测试会失败。
struct AppDatabaseSchemaSnapshotTests {
    @Test func migratedSchemaMatchesFrozenSnapshot() throws {
        let database: AppDatabase = try AppDatabase(path: Self.temporaryDatabasePath())

        let actual: String = try database.queue.read { database in
            return try Self.schemaDump(in: database)
        }

        #expect(
            actual == Self.expectedSchema,
            "Schema drifted from the frozen snapshot. Add a migration in AppDatabaseMigrations, then replace expectedSchema with:\n\(actual)"
        )
    }

    @Test func migrationLedgerMatchesRegisteredIdentifiers() throws {
        let database: AppDatabase = try AppDatabase(path: Self.temporaryDatabasePath())

        let identifiers: [String] = try database.queue.read { database in
            return try String.fetchAll(
                database,
                sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid"
            )
        }

        #expect(identifiers == AppDatabaseMigrations.identifiers)
        #expect(AppDatabase.currentSchemaMigrationIdentifier == AppDatabaseMigrations.identifiers.last)
    }

    /// 中文注释：一行一个对象：`type|name|CREATE 语句`，空白折叠成单个空格，表在前、索引在后，各自按名称排序。
    private static func schemaDump(in database: Database) throws -> String {
        let rows: [Row] = try Row.fetchAll(
            database,
            sql: """
            SELECT type, name, sql FROM sqlite_master
            WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
            ORDER BY type DESC, name
            """
        )
        return rows.map { row in
            let type: String = row["type"]
            let name: String = row["name"]
            let sql: String = row["sql"]
            let normalizedSQL: String = sql
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .joined(separator: " ")
            return "\(type)|\(name)|\(normalizedSQL)"
        }.joined(separator: "\n")
    }

    private static func temporaryDatabasePath() -> String {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseCraftSchemaSnapshotTests-\(UUID().uuidString).sqlite")
            .path
    }

    // 中文注释：v1.initial-schema 快照（取自 GRDB 6.24.1 生成的 sqlite_master）。
    private static let expectedSchema: String = """
table|cloud_account_partition_preparations|CREATE TABLE "cloud_account_partition_preparations" ("accountScope" TEXT PRIMARY KEY, "userID" TEXT NOT NULL REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE, "decision" TEXT NOT NULL, "preparedAt" DATETIME NOT NULL, "initialSyncCompletedAt" DATETIME)
table|cloud_app_user_association_attestations|CREATE TABLE "cloud_app_user_association_attestations" ("accountScope" TEXT PRIMARY KEY, "userID" TEXT NOT NULL REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE, "associatedAt" DATETIME NOT NULL)
table|cloud_record_metadata|CREATE TABLE "cloud_record_metadata" ("accountScope" TEXT NOT NULL, "recordName" TEXT NOT NULL, "systemFields" BLOB NOT NULL, "updatedAt" DATETIME NOT NULL, PRIMARY KEY ("accountScope", "recordName"))
table|comic_chapter_history|CREATE TABLE "comic_chapter_history" ("userID" TEXT NOT NULL REFERENCES "users"("id") ON DELETE CASCADE, "sourceID" TEXT NOT NULL, "comicItemID" TEXT NOT NULL, "comicTitle" TEXT NOT NULL, "chapterID" TEXT, "chapterKey" TEXT NOT NULL, "chapterURL" TEXT, "chapterTitle" TEXT NOT NULL, "visitedAt" DATETIME NOT NULL, "coverURL" TEXT, "lastReaderPageURL" TEXT, "lastPageImageURL" TEXT, "lastPageImageCacheKey" TEXT, "lastPageIndex" INTEGER, "previousChapterURL" TEXT, "nextChapterURL" TEXT, "previousChapterTitle" TEXT, "nextChapterTitle" TEXT, "sourceSnapshotJSON" TEXT, UNIQUE ("userID", "sourceID", "comicItemID", "chapterKey"))
table|favorite_items|CREATE TABLE "favorite_items" ("userID" TEXT NOT NULL REFERENCES "users"("id") ON DELETE CASCADE, "itemID" TEXT NOT NULL, "sourceID" TEXT NOT NULL, "kind" TEXT NOT NULL, "title" TEXT NOT NULL, "detailURL" TEXT NOT NULL, "coverURL" TEXT, "latestText" TEXT, "itemJSON" TEXT NOT NULL, "sourceSnapshotJSON" TEXT, "favoritedAt" DATETIME, "updatedAt" DATETIME NOT NULL, "deletedAt" DATETIME, "createdAt" DATETIME NOT NULL, PRIMARY KEY ("userID", "sourceID", "itemID"))
table|favorites|CREATE TABLE "favorites" ("userID" TEXT PRIMARY KEY REFERENCES "users"("id") ON DELETE CASCADE, "favoriteItemIDsJSON" TEXT NOT NULL, "favoriteItemsJSON" TEXT NOT NULL, "rssFavoritesJSON" TEXT, "comicFavoritesJSON" TEXT, "videoFavoritesJSON" TEXT, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL, "deletedAt" DATETIME)
table|rss_reading_history|CREATE TABLE "rss_reading_history" ("userID" TEXT NOT NULL REFERENCES "users"("id") ON DELETE CASCADE, "sourceID" TEXT NOT NULL, "itemID" TEXT NOT NULL, "dataType" TEXT NOT NULL, "title" TEXT NOT NULL, "dataContent" TEXT NOT NULL, "dataTime" DATETIME NOT NULL, "visitedAt" DATETIME NOT NULL, "detailURL" TEXT, "sourceName" TEXT, "originFeedURL" TEXT, "sourceSnapshotJSON" TEXT, UNIQUE ("userID", "sourceID", "itemID"))
table|sources|CREATE TABLE "sources" ("userID" TEXT NOT NULL REFERENCES "users"("id") ON DELETE CASCADE, "id" TEXT NOT NULL, "name" TEXT NOT NULL, "baseURL" TEXT NOT NULL, "type" TEXT NOT NULL, "kind" TEXT NOT NULL, "configJSON" TEXT NOT NULL, "enabled" BOOLEAN NOT NULL DEFAULT 1, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL, "deletedAt" DATETIME, PRIMARY KEY ("userID", "id"))
table|sync_queue|CREATE TABLE "sync_queue" ("id" TEXT PRIMARY KEY, "accountScope" TEXT NOT NULL, "entityType" TEXT NOT NULL, "entityID" TEXT NOT NULL, "operation" TEXT NOT NULL, "updatedAt" DATETIME NOT NULL, "retryCount" INTEGER NOT NULL DEFAULT 0, "lastError" TEXT, "nextRetryAt" DATETIME, "createdAt" DATETIME NOT NULL, UNIQUE ("accountScope", "entityType", "entityID"))
table|sync_state|CREATE TABLE "sync_state" ("accountScope" TEXT NOT NULL, "scope" TEXT NOT NULL, "zoneName" TEXT NOT NULL, "serverChangeTokenData" BLOB, "lastSyncedAt" DATETIME, "updatedAt" DATETIME NOT NULL, PRIMARY KEY ("accountScope", "scope", "zoneName"))
table|temporary_resource_history|CREATE TABLE "temporary_resource_history" ("userID" TEXT NOT NULL REFERENCES "users"("id") ON DELETE CASCADE, "kind" TEXT NOT NULL, "title" TEXT NOT NULL, "resourceURL" TEXT NOT NULL, "coverURL" TEXT, "sourcePageURL" TEXT, "matchedKeyword" TEXT, "videoPlaybackKind" TEXT, "visitedAt" DATETIME NOT NULL, UNIQUE ("userID", "kind", "resourceURL"))
table|user_library_state|CREATE TABLE "user_library_state" ("userID" TEXT PRIMARY KEY REFERENCES "users"("id") ON DELETE CASCADE, "selectedSourceID" TEXT, "listContextJSON" TEXT, "lastRefreshAt" DATETIME, "updatedAt" DATETIME NOT NULL)
table|user_storekit_transactions|CREATE TABLE "user_storekit_transactions" ("userID" TEXT NOT NULL REFERENCES "users"("id") ON DELETE CASCADE, "transactionID" TEXT NOT NULL, "originalTransactionID" TEXT NOT NULL, "productID" TEXT NOT NULL, "productType" TEXT NOT NULL, "environment" TEXT NOT NULL, "ownershipType" TEXT NOT NULL, "purchaseDate" DATETIME NOT NULL, "expirationDate" DATETIME, "revocationDate" DATETIME, "createdAt" DATETIME NOT NULL, PRIMARY KEY ("userID", "transactionID"))
table|users|CREATE TABLE "users" ("id" TEXT PRIMARY KEY, "displayName" TEXT, "hasRemovedAds" BOOLEAN NOT NULL DEFAULT 0, "pendingAdPoints" INTEGER NOT NULL DEFAULT 0, "siteSlotLimit" INTEGER NOT NULL DEFAULT 1, "purchasedSiteSlots" INTEGER NOT NULL DEFAULT 0, "vipExpiresAt" DATETIME, "processedStoreKitTransactionIDsJSON" TEXT, "lastStoreKitTransactionID" TEXT, "lastStoreKitOriginalTransactionID" TEXT, "lastStoreKitProductID" TEXT, "lastStoreKitProductType" TEXT, "lastStoreKitEnvironment" TEXT, "lastStoreKitOwnershipType" TEXT, "lastStoreKitPurchaseDate" DATETIME, "lastStoreKitExpirationDate" DATETIME, "lastStoreKitRevocationDate" DATETIME, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL)
table|video_watch_history|CREATE TABLE "video_watch_history" ("userID" TEXT NOT NULL REFERENCES "users"("id") ON DELETE CASCADE, "sourceID" TEXT NOT NULL, "vodID" TEXT NOT NULL, "workKey" TEXT NOT NULL, "videoTitle" TEXT NOT NULL, "episodeTitle" TEXT, "episodeKey" TEXT NOT NULL, "sourceIndex" INTEGER NOT NULL, "episodeIndex" INTEGER NOT NULL, "detailURL" TEXT, "playPageURL" TEXT NOT NULL, "candidateMediaURL" TEXT, "candidateMediaKind" TEXT NOT NULL, "playbackStatusJSON" TEXT, "playbackRequestConfigJSON" TEXT, "coverURL" TEXT, "sourceName" TEXT, "lastPlaybackTime" REAL NOT NULL DEFAULT 0, "duration" REAL, "visitedAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL, "previousEpisodeURL" TEXT, "nextEpisodeURL" TEXT, "sourceSnapshotJSON" TEXT, UNIQUE ("userID", "sourceID", "workKey"))
index|idx_comic_chapter_history_source|CREATE INDEX idx_comic_chapter_history_source ON comic_chapter_history(sourceID)
index|idx_comic_chapter_history_user_visited_at|CREATE INDEX idx_comic_chapter_history_user_visited_at ON comic_chapter_history(userID, visitedAt DESC)
index|idx_favorite_items_source|CREATE INDEX idx_favorite_items_source ON favorite_items(userID, sourceID, deletedAt)
index|idx_favorite_items_user_visible|CREATE INDEX idx_favorite_items_user_visible ON favorite_items(userID, deletedAt, favoritedAt DESC)
index|idx_rss_reading_history_source|CREATE INDEX idx_rss_reading_history_source ON rss_reading_history(sourceID)
index|idx_rss_reading_history_user_visited_at|CREATE INDEX idx_rss_reading_history_user_visited_at ON rss_reading_history(userID, visitedAt DESC)
index|idx_sources_user_updated_at|CREATE INDEX idx_sources_user_updated_at ON sources(userID, deletedAt, updatedAt DESC)
index|idx_sync_queue_entity|CREATE INDEX idx_sync_queue_entity ON sync_queue(accountScope, entityType, entityID)
index|idx_sync_queue_pending|CREATE INDEX idx_sync_queue_pending ON sync_queue(accountScope, nextRetryAt, updatedAt ASC)
index|idx_temporary_resource_history_user_visited_at|CREATE INDEX idx_temporary_resource_history_user_visited_at ON temporary_resource_history(userID, visitedAt DESC)
index|idx_user_library_state_selected_source|CREATE INDEX idx_user_library_state_selected_source ON user_library_state(selectedSourceID)
index|idx_user_storekit_transactions_original_transaction|CREATE INDEX idx_user_storekit_transactions_original_transaction ON user_storekit_transactions(userID, originalTransactionID)
index|idx_user_storekit_transactions_product|CREATE INDEX idx_user_storekit_transactions_product ON user_storekit_transactions(userID, productID, purchaseDate DESC)
index|idx_video_watch_history_detail_url|CREATE INDEX idx_video_watch_history_detail_url ON video_watch_history(userID, sourceID, detailURL)
index|idx_video_watch_history_source|CREATE INDEX idx_video_watch_history_source ON video_watch_history(sourceID)
index|idx_video_watch_history_user_updated_at|CREATE INDEX idx_video_watch_history_user_updated_at ON video_watch_history(userID, updatedAt DESC)
index|idx_video_watch_history_video_title|CREATE INDEX idx_video_watch_history_video_title ON video_watch_history(userID, sourceID, videoTitle)
"""
}
