import GRDB

extension SyncStateRecord {
    enum Columns {
        static let accountScope: Column = Column("accountScope")
        static let scope: Column = Column("scope")
        static let zoneName: Column = Column("zoneName")
        static let serverChangeTokenData: Column = Column("serverChangeTokenData")
        static let lastSyncedAt: Column = Column("lastSyncedAt")
        static let updatedAt: Column = Column("updatedAt")
    }

    /// 中文注释：sync_state 保存 CloudKit change token 这类同步游标，不保存业务数据。
    /// 中文注释：accountScope + scope + zoneName 隔离账户、Cloud database scope 和 zone。
    static func createTable(in database: Database) throws {
        try database.create(table: Self.databaseTableName, ifNotExists: true) { table in
            table.column("accountScope", .text).notNull()
            table.column("scope", .text).notNull()
            table.column("zoneName", .text).notNull()
            table.column("serverChangeTokenData", .blob)
            table.column("lastSyncedAt", .datetime)
            table.column("updatedAt", .datetime).notNull()
            table.primaryKey(["accountScope", "scope", "zoneName"])
        }
    }

    /// 中文注释：sync_state 通过复合主键读取，不需要额外索引。
    static func createIndexes(in database: Database) throws {
        _ = database
    }
}
