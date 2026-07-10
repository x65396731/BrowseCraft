import GRDB

extension RSSReadingHistoryRecord {
    enum Columns {
        static let userID: Column = Column("userID")
        static let sourceID: Column = Column("sourceID")
        static let itemID: Column = Column("itemID")
        static let dataType: Column = Column("dataType")
        static let title: Column = Column("title")
        static let dataContent: Column = Column("dataContent")
        static let dataTime: Column = Column("dataTime")
        static let visitedAt: Column = Column("visitedAt")
        static let detailURL: Column = Column("detailURL")
        static let sourceName: Column = Column("sourceName")
        static let originFeedURL: Column = Column("originFeedURL")
        static let sourceSnapshotJSON: Column = Column("sourceSnapshotJSON")
    }

    /// 中文注释：rss_reading_history 保存 RSS 条目阅读历史快照，不保存 feed 列表缓存。
    /// 中文注释：userID + sourceID + itemID 唯一，重复阅读同一条目会覆盖最近访问时间。
    static func createTable(in database: Database) throws {
        try database.create(table: Self.databaseTableName, ifNotExists: true) { table in
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
            table.column("sourceSnapshotJSON", .text)
            table.uniqueKey(["userID", "sourceID", "itemID"])
        }
    }

    /// 中文注释：历史页按用户和访问时间倒序读取；sourceID 索引用于删除或筛选某个来源相关历史。
    static func createIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_rss_reading_history_user_visited_at
            ON \(Self.databaseTableName)(userID, visitedAt DESC)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_rss_reading_history_source
            ON \(Self.databaseTableName)(sourceID)
            """
        )
    }
}
