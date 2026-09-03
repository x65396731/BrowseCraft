@preconcurrency import GRDB

extension UserLibraryStateRecord {
    enum Columns {
        static let userID: Column = Column("userID")
        static let selectedSourceID: Column = Column("selectedSourceID")
        static let listContextJSON: Column = Column("listContextJSON")
        static let lastRefreshAt: Column = Column("lastRefreshAt")
        static let updatedAt: Column = Column("updatedAt")
    }
}
