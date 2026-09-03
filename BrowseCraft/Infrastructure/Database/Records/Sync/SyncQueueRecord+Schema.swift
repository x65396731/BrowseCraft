@preconcurrency import GRDB

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
}
