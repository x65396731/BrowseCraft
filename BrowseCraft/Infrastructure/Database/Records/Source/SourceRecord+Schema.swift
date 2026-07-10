import GRDB

extension SourceRecord {
    enum Columns {
        static let id: Column = Column("id")
        static let name: Column = Column("name")
        static let baseURL: Column = Column("baseURL")
        static let type: Column = Column("type")
        static let kind: Column = Column("kind")
        static let configJSON: Column = Column("configJSON")
        static let enabled: Column = Column("enabled")
        static let createdAt: Column = Column("createdAt")
        static let updatedAt: Column = Column("updatedAt")
        static let deletedAt: Column = Column("deletedAt")
    }

    /// 中文注释：sources 保存用户可选择的站点来源配置；不保存列表内容、详情内容或缓存文件。
    /// 中文注释：deletedAt 用于软删除，便于未来 iCloud 把删除动作同步到其他设备。
    static func createTable(in database: Database) throws {
        try database.create(table: Self.databaseTableName, ifNotExists: true) { table in
            table.column("id", .text).primaryKey()
            table.column("name", .text).notNull()
            table.column("baseURL", .text).notNull()
            table.column("type", .text).notNull()
            table.column("kind", .text).notNull()
            table.column("configJSON", .text).notNull()
            table.column("enabled", .boolean).notNull().defaults(to: true)
            table.column("createdAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("deletedAt", .datetime)
        }
    }

    /// 中文注释：来源列表只展示未软删除记录，并按最近更新时间排序。
    static func createIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_sources_updated_at
            ON \(Self.databaseTableName)(deletedAt, updatedAt DESC)
            """
        )
    }
}
