@preconcurrency import GRDB

extension SyncStateRecord {
    enum Columns {
        static let accountScope: Column = Column("accountScope")
        static let scope: Column = Column("scope")
        static let zoneName: Column = Column("zoneName")
        static let serverChangeTokenData: Column = Column("serverChangeTokenData")
        static let lastSyncedAt: Column = Column("lastSyncedAt")
        static let updatedAt: Column = Column("updatedAt")
    }
}
