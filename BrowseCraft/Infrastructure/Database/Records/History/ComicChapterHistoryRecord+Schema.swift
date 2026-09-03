@preconcurrency import GRDB

extension ComicChapterHistoryRecord {
    enum Columns {
        static let userID: Column = Column("userID")
        static let sourceID: Column = Column("sourceID")
        static let comicItemID: Column = Column("comicItemID")
        static let comicTitle: Column = Column("comicTitle")
        static let chapterID: Column = Column("chapterID")
        static let chapterKey: Column = Column("chapterKey")
        static let chapterURL: Column = Column("chapterURL")
        static let chapterTitle: Column = Column("chapterTitle")
        static let visitedAt: Column = Column("visitedAt")
        static let coverURL: Column = Column("coverURL")
        static let lastReaderPageURL: Column = Column("lastReaderPageURL")
        static let lastPageImageURL: Column = Column("lastPageImageURL")
        static let lastPageImageCacheKey: Column = Column("lastPageImageCacheKey")
        static let lastPageIndex: Column = Column("lastPageIndex")
        static let previousChapterURL: Column = Column("previousChapterURL")
        static let nextChapterURL: Column = Column("nextChapterURL")
        static let previousChapterTitle: Column = Column("previousChapterTitle")
        static let nextChapterTitle: Column = Column("nextChapterTitle")
        static let sourceSnapshotJSON: Column = Column("sourceSnapshotJSON")
    }
}
