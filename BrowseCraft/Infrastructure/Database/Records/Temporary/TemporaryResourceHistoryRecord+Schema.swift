import GRDB

extension TemporaryResourceHistoryRecord {
    enum Columns {
        static let userID: Column = Column("userID")
        static let kind: Column = Column("kind")
        static let title: Column = Column("title")
        static let resourceURL: Column = Column("resourceURL")
        static let coverURL: Column = Column("coverURL")
        static let sourcePageURL: Column = Column("sourcePageURL")
        static let matchedKeyword: Column = Column("matchedKeyword")
        static let videoPlaybackKind: Column = Column("videoPlaybackKind")
        static let visitedAt: Column = Column("visitedAt")
    }

    /// 中文注释：temporary_resource_history 保存临时发现资源，供历史页兜底展示。
    /// 中文注释：userID + kind + resourceURL 唯一，避免同一临时资源反复插入。
    static func createTable(in database: Database) throws {
        try database.create(table: Self.databaseTableName, ifNotExists: true) { table in
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

    /// 中文注释：临时资源历史按用户和访问时间倒序读取。
    static func createIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_temporary_resource_history_user_visited_at
            ON \(Self.databaseTableName)(userID, visitedAt DESC)
            """
        )
    }
}
