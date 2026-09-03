@preconcurrency import GRDB

extension SourceRecord {
    enum Columns {
        static let userID: Column = Column("userID")
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
}
