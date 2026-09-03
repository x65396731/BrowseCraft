@preconcurrency import GRDB

extension FavoriteItemRecord {
    enum Columns {
        static let userID: Column = Column("userID")
        static let itemID: Column = Column("itemID")
        static let sourceID: Column = Column("sourceID")
        static let kind: Column = Column("kind")
        static let title: Column = Column("title")
        static let detailURL: Column = Column("detailURL")
        static let coverURL: Column = Column("coverURL")
        static let latestText: Column = Column("latestText")
        static let itemJSON: Column = Column("itemJSON")
        static let sourceSnapshotJSON: Column = Column("sourceSnapshotJSON")
        static let favoritedAt: Column = Column("favoritedAt")
        static let updatedAt: Column = Column("updatedAt")
        static let deletedAt: Column = Column("deletedAt")
        static let createdAt: Column = Column("createdAt")
    }
}
