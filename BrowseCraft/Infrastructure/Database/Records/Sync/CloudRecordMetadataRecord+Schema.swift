import GRDB

extension CloudRecordMetadataRecord {
    enum Columns {
        static let accountScope: Column = Column("accountScope")
        static let recordName: Column = Column("recordName")
        static let systemFields: Column = Column("systemFields")
        static let updatedAt: Column = Column("updatedAt")
    }

    static func createTable(in database: Database) throws {
        try database.create(table: Self.databaseTableName, ifNotExists: true) { table in
            table.column("accountScope", .text)
                .notNull()
                .references(AppUserRecord.databaseTableName, column: "id", onDelete: .cascade)
            table.column("recordName", .text).notNull()
            table.column("systemFields", .blob).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.primaryKey(["accountScope", "recordName"])
        }
    }
}
