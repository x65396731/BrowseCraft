@preconcurrency import GRDB

// 中文注释：`v1.initial-schema` 的冻结快照。TestFlight 与真机上已经记录了这次迁移，
// 这里的任何改动都不会再作用到它们——schema 变更只能在 AppDatabaseMigrations 追加 v2+ 迁移，
// 并同步更新 AppDatabaseSchemaSnapshotTests 的快照。
// 表名、列名全部是字面量，不再引用 Record，避免 Record 演进悄悄改写历史迁移。
// `ifNotExists` 只为纳入迁移账本之前创建的开发数据库；新数据库总是从这里建表。
enum AppDatabaseSchemaV1 {
    static let identifier: String = "v1.initial-schema"

    static func apply(to database: Database) throws {
        try Self.createTables(in: database)
        try Self.createIndexes(in: database)
    }

    private static func createTables(in database: Database) throws {
        try Self.createAppUserTable(in: database)
        try Self.createCloudAccountPartitionPreparationTable(in: database)
        try Self.createCloudAppUserAssociationAttestationTable(in: database)
        try Self.createSourceTable(in: database)
        try Self.createFavoriteTable(in: database)
        try Self.createFavoriteItemTable(in: database)
        try Self.createUserStoreKitTransactionTable(in: database)
        try Self.createSyncStateTable(in: database)
        try Self.createSyncQueueTable(in: database)
        try Self.createCloudRecordMetadataTable(in: database)
        try Self.createRSSReadingHistoryTable(in: database)
        try Self.createComicChapterHistoryTable(in: database)
        try Self.createUserLibraryStateTable(in: database)
        try Self.createVideoWatchHistoryTable(in: database)
        try Self.createTemporaryResourceHistoryTable(in: database)
    }

    private static func createIndexes(in database: Database) throws {
        try Self.createSourceIndexes(in: database)
        try Self.createFavoriteItemIndexes(in: database)
        try Self.createRSSReadingHistoryIndexes(in: database)
        try Self.createComicChapterHistoryIndexes(in: database)
        try Self.createVideoWatchHistoryIndexes(in: database)
        try Self.createUserLibraryStateIndexes(in: database)
        try Self.createUserStoreKitTransactionIndexes(in: database)
        try Self.createSyncQueueIndexes(in: database)
        try Self.createTemporaryResourceHistoryIndexes(in: database)
    }

    // MARK: - users

    /// 中文注释：users 是本地业务用户根表，保存权益快照和最近一次 StoreKit 交易摘要。
    /// 中文注释：完整交易明细放在 user_storekit_transactions，避免 users 表无限增长。
    private static func createAppUserTable(in database: Database) throws {
        try database.create(table: "users", ifNotExists: true) { table in
            table.column("id", .text).primaryKey()
            table.column("displayName", .text)
            table.column("hasRemovedAds", .boolean).notNull().defaults(to: false)
            table.column("pendingAdPoints", .integer).notNull().defaults(to: 0)
            table.column("siteSlotLimit", .integer).notNull().defaults(to: 1)
            table.column("purchasedSiteSlots", .integer).notNull().defaults(to: 0)
            table.column("vipExpiresAt", .datetime)
            table.column("processedStoreKitTransactionIDsJSON", .text)
            table.column("lastStoreKitTransactionID", .text)
            table.column("lastStoreKitOriginalTransactionID", .text)
            table.column("lastStoreKitProductID", .text)
            table.column("lastStoreKitProductType", .text)
            table.column("lastStoreKitEnvironment", .text)
            table.column("lastStoreKitOwnershipType", .text)
            table.column("lastStoreKitPurchaseDate", .datetime)
            table.column("lastStoreKitExpirationDate", .datetime)
            table.column("lastStoreKitRevocationDate", .datetime)
            table.column("createdAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
        }
    }

    // MARK: - cloud_account_partition_preparations

    private static func createCloudAccountPartitionPreparationTable(in database: Database) throws {
        try database.create(table: "cloud_account_partition_preparations", ifNotExists: true) { table in
            table.column("accountScope", .text)
                .primaryKey()
            table.column("userID", .text)
                .notNull()
                .references(
                    "users",
                    onDelete: .cascade,
                    onUpdate: .cascade
                )
            table.column("decision", .text).notNull()
            table.column("preparedAt", .datetime).notNull()
            table.column("initialSyncCompletedAt", .datetime)
        }
    }

    // MARK: - cloud_app_user_association_attestations

    private static func createCloudAppUserAssociationAttestationTable(in database: Database) throws {
        try database.create(table: "cloud_app_user_association_attestations", ifNotExists: true) { table in
            table.column("accountScope", .text).primaryKey()
            table.column("userID", .text)
                .notNull()
                .references(
                    "users",
                    onDelete: .cascade,
                    onUpdate: .cascade
                )
            table.column("associatedAt", .datetime).notNull()
        }
    }

    // MARK: - sources

    /// 中文注释：sources 保存用户可选择的站点来源配置；不保存列表内容、详情内容或缓存文件。
    /// 中文注释：userID + id 允许不同本地账户空间保存相同业务 Source ID。
    /// 中文注释：deletedAt 用于软删除，便于未来 iCloud 把删除动作同步到其他设备。
    private static func createSourceTable(in database: Database) throws {
        try database.create(table: "sources", ifNotExists: true) { table in
            table.column("userID", .text)
                .notNull()
                .references("users", column: "id", onDelete: .cascade)
            table.column("id", .text).notNull()
            table.column("name", .text).notNull()
            table.column("baseURL", .text).notNull()
            table.column("type", .text).notNull()
            table.column("kind", .text).notNull()
            table.column("configJSON", .text).notNull()
            table.column("enabled", .boolean).notNull().defaults(to: true)
            table.column("createdAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("deletedAt", .datetime)
            table.primaryKey(["userID", "id"])
        }
    }

    /// 中文注释：来源列表只展示未软删除记录，并按最近更新时间排序。
    private static func createSourceIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_sources_user_updated_at
            ON sources(userID, deletedAt, updatedAt DESC)
            """
        )
    }

    // MARK: - favorites

    /// 中文注释：favorites 按 userID 聚合收藏快照，当前不拆成每条收藏一行。
    /// 中文注释：deletedAt 为未来整组收藏云端删除或重置预留。
    private static func createFavoriteTable(in database: Database) throws {
        try database.create(table: "favorites", ifNotExists: true) { table in
            table.column("userID", .text)
                .primaryKey()
                .references("users", column: "id", onDelete: .cascade)
            table.column("favoriteItemIDsJSON", .text).notNull()
            table.column("favoriteItemsJSON", .text).notNull()
            table.column("rssFavoritesJSON", .text)
            table.column("comicFavoritesJSON", .text)
            table.column("videoFavoritesJSON", .text)
            table.column("createdAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("deletedAt", .datetime)
        }
    }

    // MARK: - favorite_items

    /// 中文注释：favorite_items 是收藏同步明细表，一行表示一个收藏 item。
    /// 中文注释：取消收藏写 deletedAt tombstone，不物理删除，保证其他设备能收到删除意图。
    private static func createFavoriteItemTable(in database: Database) throws {
        try database.create(table: "favorite_items", ifNotExists: true) { table in
            table.column("userID", .text)
                .notNull()
                .references("users", column: "id", onDelete: .cascade)
            table.column("itemID", .text).notNull()
            table.column("sourceID", .text).notNull()
            table.column("kind", .text).notNull()
            table.column("title", .text).notNull()
            table.column("detailURL", .text).notNull()
            table.column("coverURL", .text)
            table.column("latestText", .text)
            table.column("itemJSON", .text).notNull()
            table.column("sourceSnapshotJSON", .text)
            table.column("favoritedAt", .datetime)
            table.column("updatedAt", .datetime).notNull()
            table.column("deletedAt", .datetime)
            table.column("createdAt", .datetime).notNull()
            table.primaryKey(["userID", "sourceID", "itemID"])
        }
    }

    /// 中文注释：列表重建按 userID + deletedAt + favoritedAt 读取；sourceID 索引用于来源相关排查。
    private static func createFavoriteItemIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_favorite_items_user_visible
            ON favorite_items(userID, deletedAt, favoritedAt DESC)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_favorite_items_source
            ON favorite_items(userID, sourceID, deletedAt)
            """
        )
    }

    // MARK: - user_storekit_transactions

    /// 中文注释：user_storekit_transactions 保存用户处理过的 StoreKit 交易明细，用于去重和重建权益。
    /// 中文注释：主键 userID + transactionID 保证同一用户同一交易只应用一次。
    private static func createUserStoreKitTransactionTable(in database: Database) throws {
        try database.create(table: "user_storekit_transactions", ifNotExists: true) { table in
            table.column("userID", .text)
                .notNull()
                .references("users", column: "id", onDelete: .cascade)
            table.column("transactionID", .text).notNull()
            table.column("originalTransactionID", .text).notNull()
            table.column("productID", .text).notNull()
            table.column("productType", .text).notNull()
            table.column("environment", .text).notNull()
            table.column("ownershipType", .text).notNull()
            table.column("purchaseDate", .datetime).notNull()
            table.column("expirationDate", .datetime)
            table.column("revocationDate", .datetime)
            table.column("createdAt", .datetime).notNull()
            table.primaryKey(["userID", "transactionID"])
        }
    }

    /// 中文注释：originalTransactionID 用于查订阅链，productID + purchaseDate 用于按商品回看购买记录。
    private static func createUserStoreKitTransactionIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_user_storekit_transactions_original_transaction
            ON user_storekit_transactions(userID, originalTransactionID)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_user_storekit_transactions_product
            ON user_storekit_transactions(userID, productID, purchaseDate DESC)
            """
        )
    }

    // MARK: - sync_state

    /// 中文注释：sync_state 保存 CloudKit change token 这类同步游标，不保存业务数据。
    /// 中文注释：accountScope + scope + zoneName 隔离账户、Cloud database scope 和 zone。
    private static func createSyncStateTable(in database: Database) throws {
        try database.create(table: "sync_state", ifNotExists: true) { table in
            table.column("accountScope", .text).notNull()
            table.column("scope", .text).notNull()
            table.column("zoneName", .text).notNull()
            table.column("serverChangeTokenData", .blob)
            table.column("lastSyncedAt", .datetime)
            table.column("updatedAt", .datetime).notNull()
            table.primaryKey(["accountScope", "scope", "zoneName"])
        }
    }

    // MARK: - sync_queue

    /// 中文注释：sync_queue 保存本机尚未上传到云端的变更队列。
    /// 中文注释：accountScope + entityType + entityID 唯一，账户之间的同名记录不会合并队列。
    private static func createSyncQueueTable(in database: Database) throws {
        try database.create(table: "sync_queue", ifNotExists: true) { table in
            table.column("id", .text).primaryKey()
            table.column("accountScope", .text).notNull()
            table.column("entityType", .text).notNull()
            table.column("entityID", .text).notNull()
            table.column("operation", .text).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("retryCount", .integer).notNull().defaults(to: 0)
            table.column("lastError", .text)
            table.column("nextRetryAt", .datetime)
            table.column("createdAt", .datetime).notNull()
            table.uniqueKey(["accountScope", "entityType", "entityID"])
        }
    }

    /// 中文注释：pending 索引用于同步器按时间取队列；entity 索引用于本地变更入队时快速合并。
    private static func createSyncQueueIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_sync_queue_pending
            ON sync_queue(accountScope, nextRetryAt, updatedAt ASC)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_sync_queue_entity
            ON sync_queue(accountScope, entityType, entityID)
            """
        )
    }

    // MARK: - cloud_record_metadata

    private static func createCloudRecordMetadataTable(in database: Database) throws {
        try database.create(table: "cloud_record_metadata", ifNotExists: true) { table in
            table.column("accountScope", .text)
                .notNull()
            table.column("recordName", .text).notNull()
            table.column("systemFields", .blob).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.primaryKey(["accountScope", "recordName"])
        }
    }

    // MARK: - rss_reading_history

    /// 中文注释：rss_reading_history 保存 RSS 条目阅读历史快照，不保存 feed 列表缓存。
    /// 中文注释：userID + sourceID + itemID 唯一，重复阅读同一条目会覆盖最近访问时间。
    private static func createRSSReadingHistoryTable(in database: Database) throws {
        try database.create(table: "rss_reading_history", ifNotExists: true) { table in
            table.column("userID", .text)
                .notNull()
                .references("users", column: "id", onDelete: .cascade)
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
            table.column("sourceSnapshotJSON", .text)
            table.uniqueKey(["userID", "sourceID", "itemID"])
        }
    }

    /// 中文注释：历史页按用户和访问时间倒序读取；sourceID 索引用于删除或筛选某个来源相关历史。
    private static func createRSSReadingHistoryIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_rss_reading_history_user_visited_at
            ON rss_reading_history(userID, visitedAt DESC)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_rss_reading_history_source
            ON rss_reading_history(sourceID)
            """
        )
    }

    // MARK: - comic_chapter_history

    /// 中文注释：comic_chapter_history 保存漫画章节阅读历史和最后阅读位置。
    /// 中文注释：userID + sourceID + comicItemID + chapterKey 唯一，确保同一章节只保留一条进度。
    private static func createComicChapterHistoryTable(in database: Database) throws {
        try database.create(table: "comic_chapter_history", ifNotExists: true) { table in
            table.column("userID", .text)
                .notNull()
                .references("users", column: "id", onDelete: .cascade)
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
            table.column("previousChapterTitle", .text)
            table.column("nextChapterTitle", .text)
            table.column("sourceSnapshotJSON", .text)
            table.uniqueKey(["userID", "sourceID", "comicItemID", "chapterKey"])
        }
    }

    /// 中文注释：历史页按用户和访问时间倒序读取；sourceID 索引用于来源删除后的关联处理。
    private static func createComicChapterHistoryIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_comic_chapter_history_user_visited_at
            ON comic_chapter_history(userID, visitedAt DESC)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_comic_chapter_history_source
            ON comic_chapter_history(sourceID)
            """
        )
    }

    // MARK: - user_library_state

    /// 中文注释：user_library_state 保存用户在 Library 页的当前来源和分页上下文。
    /// 中文注释：这里不保存列表 items，刷新后由对应 SourceRuntime 重新加载。
    private static func createUserLibraryStateTable(in database: Database) throws {
        try database.create(table: "user_library_state", ifNotExists: true) { table in
            table.column("userID", .text)
                .primaryKey()
                .references("users", column: "id", onDelete: .cascade)
            table.column("selectedSourceID", .text)
            table.column("listContextJSON", .text)
            table.column("lastRefreshAt", .datetime)
            table.column("updatedAt", .datetime).notNull()
        }
    }

    /// 中文注释：selectedSourceID 索引用于来源软删除时快速清理当前选择。
    private static func createUserLibraryStateIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_user_library_state_selected_source
            ON user_library_state(selectedSourceID)
            """
        )
    }

    // MARK: - video_watch_history

    /// 中文注释：video_watch_history 保存视频播放历史、播放进度和播放请求快照。
    /// 中文注释：userID + sourceID + workKey 唯一，workKey 兼容 vodID 为空时使用详情页或标题兜底。
    private static func createVideoWatchHistoryTable(in database: Database) throws {
        try database.create(table: "video_watch_history", ifNotExists: true) { table in
            table.column("userID", .text)
                .notNull()
                .references("users", column: "id", onDelete: .cascade)
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
            table.column("sourceSnapshotJSON", .text)
            table.uniqueKey(["userID", "sourceID", "workKey"])
        }
    }

    /// 中文注释：历史页按 updatedAt/visitedAt 排序；详情页和标题索引用于播放历史合并与清理。
    private static func createVideoWatchHistoryIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_video_watch_history_user_updated_at
            ON video_watch_history(userID, updatedAt DESC)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_video_watch_history_detail_url
            ON video_watch_history(userID, sourceID, detailURL)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_video_watch_history_video_title
            ON video_watch_history(userID, sourceID, videoTitle)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_video_watch_history_source
            ON video_watch_history(sourceID)
            """
        )
    }

    // MARK: - temporary_resource_history

    /// 中文注释：temporary_resource_history 保存临时发现资源，供历史页兜底展示。
    /// 中文注释：userID + kind + resourceURL 唯一，避免同一临时资源反复插入。
    private static func createTemporaryResourceHistoryTable(in database: Database) throws {
        try database.create(table: "temporary_resource_history", ifNotExists: true) { table in
            table.column("userID", .text)
                .notNull()
                .references("users", column: "id", onDelete: .cascade)
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

    /// 中文注释：临时资源历史按用户和访问时间倒序读取。
    private static func createTemporaryResourceHistoryIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_temporary_resource_history_user_visited_at
            ON temporary_resource_history(userID, visitedAt DESC)
            """
        )
    }
}
