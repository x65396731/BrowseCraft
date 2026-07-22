import GRDB

extension FavoriteItemRecord {
    enum Columns {
        static let userID: Column = Column("userID")
        static let itemID: Column = Column("itemID")
        static let sourceID: Column = Column("sourceID")
        static let kind: Column = Column("kind")
        static let title: Column = Column("title")
        static let detailURL: Column = Column("detailURL")
        static let coverURL: Column = Column("coverURL")
        static let latestText: Column = Column("latestText")
        static let itemJSON: Column = Column("itemJSON")
        static let sourceSnapshotJSON: Column = Column("sourceSnapshotJSON")
        static let favoritedAt: Column = Column("favoritedAt")
        static let updatedAt: Column = Column("updatedAt")
        static let deletedAt: Column = Column("deletedAt")
        static let createdAt: Column = Column("createdAt")
    }

    /// 中文注释：favorite_items 是收藏同步明细表，一行表示一个收藏 item。
    /// 中文注释：取消收藏写 deletedAt tombstone，不物理删除，保证其他设备能收到删除意图。
    static func createTable(in database: Database) throws {
        try database.create(table: Self.databaseTableName, ifNotExists: true) { table in
            table.column("userID", .text)
                .notNull()
                .references(AppUserRecord.databaseTableName, column: "id", onDelete: .cascade)
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
    static func createIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_favorite_items_user_visible
            ON \(Self.databaseTableName)(userID, deletedAt, favoritedAt DESC)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_favorite_items_source
            ON \(Self.databaseTableName)(userID, sourceID, deletedAt)
            """
        )
    }
}
