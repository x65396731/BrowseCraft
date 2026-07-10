import GRDB

extension UserLibraryStateRecord {
    enum Columns {
        static let userID: Column = Column("userID")
        static let selectedSourceID: Column = Column("selectedSourceID")
        static let listContextJSON: Column = Column("listContextJSON")
        static let lastRefreshAt: Column = Column("lastRefreshAt")
        static let updatedAt: Column = Column("updatedAt")
    }

    /// 中文注释：user_library_state 保存用户在 Library 页的当前来源和分页上下文。
    /// 中文注释：这里不保存列表 items，刷新后由对应 SourceRuntime 重新加载。
    static func createTable(in database: Database) throws {
        try database.create(table: Self.databaseTableName, ifNotExists: true) { table in
            table.column("userID", .text)
                .primaryKey()
                .references(AppUserRecord.databaseTableName, column: "id", onDelete: .cascade)
            table.column("selectedSourceID", .text)
            table.column("listContextJSON", .text)
            table.column("lastRefreshAt", .datetime)
            table.column("updatedAt", .datetime).notNull()
        }
    }

    /// 中文注释：selectedSourceID 索引用于来源软删除时快速清理当前选择。
    static func createIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_user_library_state_selected_source
            ON \(Self.databaseTableName)(selectedSourceID)
            """
        )
    }
}
