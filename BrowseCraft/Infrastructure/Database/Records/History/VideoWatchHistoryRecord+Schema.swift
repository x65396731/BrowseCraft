import GRDB

extension VideoWatchHistoryRecord {
    enum Columns {
        static let userID: Column = Column("userID")
        static let sourceID: Column = Column("sourceID")
        static let vodID: Column = Column("vodID")
        static let workKey: Column = Column("workKey")
        static let videoTitle: Column = Column("videoTitle")
        static let episodeTitle: Column = Column("episodeTitle")
        static let episodeKey: Column = Column("episodeKey")
        static let sourceIndex: Column = Column("sourceIndex")
        static let episodeIndex: Column = Column("episodeIndex")
        static let detailURL: Column = Column("detailURL")
        static let playPageURL: Column = Column("playPageURL")
        static let candidateMediaURL: Column = Column("candidateMediaURL")
        static let candidateMediaKind: Column = Column("candidateMediaKind")
        static let playbackStatusJSON: Column = Column("playbackStatusJSON")
        static let playbackRequestConfigJSON: Column = Column("playbackRequestConfigJSON")
        static let coverURL: Column = Column("coverURL")
        static let sourceName: Column = Column("sourceName")
        static let lastPlaybackTime: Column = Column("lastPlaybackTime")
        static let duration: Column = Column("duration")
        static let visitedAt: Column = Column("visitedAt")
        static let updatedAt: Column = Column("updatedAt")
        static let previousEpisodeURL: Column = Column("previousEpisodeURL")
        static let nextEpisodeURL: Column = Column("nextEpisodeURL")
        static let sourceSnapshotJSON: Column = Column("sourceSnapshotJSON")
    }

    /// 中文注释：video_watch_history 保存视频播放历史、播放进度和播放请求快照。
    /// 中文注释：userID + sourceID + workKey 唯一，workKey 兼容 vodID 为空时使用详情页或标题兜底。
    static func createTable(in database: Database) throws {
        try database.create(table: Self.databaseTableName, ifNotExists: true) { table in
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
            table.column("sourceSnapshotJSON", .text)
            table.uniqueKey(["userID", "sourceID", "workKey"])
        }
    }

    /// 中文注释：历史页按 updatedAt/visitedAt 排序；详情页和标题索引用于播放历史合并与清理。
    static func createIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_video_watch_history_user_updated_at
            ON \(Self.databaseTableName)(userID, updatedAt DESC)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_video_watch_history_detail_url
            ON \(Self.databaseTableName)(userID, sourceID, detailURL)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_video_watch_history_video_title
            ON \(Self.databaseTableName)(userID, sourceID, videoTitle)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_video_watch_history_source
            ON \(Self.databaseTableName)(sourceID)
            """
        )
    }
}
