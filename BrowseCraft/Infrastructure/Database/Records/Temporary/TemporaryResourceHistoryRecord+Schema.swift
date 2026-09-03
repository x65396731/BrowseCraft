@preconcurrency import GRDB

extension TemporaryResourceHistoryRecord {
    enum Columns {
        static let userID: Column = Column("userID")
        static let kind: Column = Column("kind")
        static let title: Column = Column("title")
        static let resourceURL: Column = Column("resourceURL")
        static let coverURL: Column = Column("coverURL")
        static let sourcePageURL: Column = Column("sourcePageURL")
        static let matchedKeyword: Column = Column("matchedKeyword")
        static let videoPlaybackKind: Column = Column("videoPlaybackKind")
        static let visitedAt: Column = Column("visitedAt")
    }
}
