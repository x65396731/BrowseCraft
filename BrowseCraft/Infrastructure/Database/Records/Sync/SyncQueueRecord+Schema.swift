import GRDB

extension SyncQueueRecord {
    enum Columns {
        static let id: Column = Column("id")
        static let entityType: Column = Column("entityType")
        static let entityID: Column = Column("entityID")
        static let operation: Column = Column("operation")
        static let updatedAt: Column = Column("updatedAt")
        static let retryCount: Column = Column("retryCount")
        static let lastError: Column = Column("lastError")
        static let createdAt: Column = Column("createdAt")
    }

    /// 中文注释：sync_queue 保存本机尚未上传到云端的变更队列。
    /// 中文注释：entityType + entityID 唯一，保证同一业务对象的多次本地修改会合并为最后一次待同步状态。
    static func createTable(in database: Database) throws {
        try database.create(table: Self.databaseTableName, ifNotExists: true) { table in
            table.column("id", .text).primaryKey()
            table.column("entityType", .text).notNull()
            table.column("entityID", .text).notNull()
            table.column("operation", .text).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("retryCount", .integer).notNull().defaults(to: 0)
            table.column("lastError", .text)
            table.column("createdAt", .datetime).notNull()
            table.uniqueKey(["entityType", "entityID"])
        }
    }

    /// 中文注释：pending 索引用于同步器按时间取队列；entity 索引用于本地变更入队时快速合并。
    static func createIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_sync_queue_pending
            ON \(Self.databaseTableName)(updatedAt ASC)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_sync_queue_entity
            ON \(Self.databaseTableName)(entityType, entityID)
            """
        )
    }
}
