@preconcurrency import GRDB

extension RSSReadingHistoryRecord {
    enum Columns {
        static let userID: Column = Column("userID")
        static let sourceID: Column = Column("sourceID")
        static let itemID: Column = Column("itemID")
        static let dataType: Column = Column("dataType")
        static let title: Column = Column("title")
        static let dataContent: Column = Column("dataContent")
        static let dataTime: Column = Column("dataTime")
        static let visitedAt: Column = Column("visitedAt")
        static let detailURL: Column = Column("detailURL")
        static let sourceName: Column = Column("sourceName")
        static let originFeedURL: Column = Column("originFeedURL")
        static let sourceSnapshotJSON: Column = Column("sourceSnapshotJSON")
    }
}
