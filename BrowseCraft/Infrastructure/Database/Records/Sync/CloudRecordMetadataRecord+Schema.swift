@preconcurrency import GRDB

extension CloudRecordMetadataRecord {
    enum Columns {
        static let accountScope: Column = Column("accountScope")
        static let recordName: Column = Column("recordName")
        static let systemFields: Column = Column("systemFields")
        static let updatedAt: Column = Column("updatedAt")
    }
}
