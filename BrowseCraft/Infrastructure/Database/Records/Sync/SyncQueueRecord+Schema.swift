import GRDB

extension SyncQueueRecord {
    enum Columns {
        static let id: Column = Column("id")
        static let accountScope: Column = Column("accountScope")
        static let entityType: Column = Column("entityType")
        static let entityID: Column = Column("entityID")
        static let operation: Column = Column("operation")
        static let updatedAt: Column = Column("updatedAt")
        static let retryCount: Column = Column("retryCount")
        static let lastError: Column = Column("lastError")
        static let nextRetryAt: Column = Column("nextRetryAt")
        static let createdAt: Column = Column("createdAt")
    }

    /// 中文注释：sync_queue 保存本机尚未上传到云端的变更队列。
    /// 中文注释：accountScope + entityType + entityID 唯一，账户之间的同名记录不会合并队列。
    static func createTable(in database: Database) throws {
        try database.create(table: Self.databaseTableName, ifNotExists: true) { table in
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
    static func createIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_sync_queue_pending
            ON \(Self.databaseTableName)(accountScope, nextRetryAt, updatedAt ASC)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_sync_queue_entity
            ON \(Self.databaseTableName)(accountScope, entityType, entityID)
            """
        )
    }
}
