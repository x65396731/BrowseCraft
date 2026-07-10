import GRDB

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
        static let sourceSnapshotJSON: Column = Column("sourceSnapshotJSON")
    }

    /// 中文注释：comic_chapter_history 保存漫画章节阅读历史和最后阅读位置。
    /// 中文注释：userID + sourceID + comicItemID + chapterKey 唯一，确保同一章节只保留一条进度。
    static func createTable(in database: Database) throws {
        try database.create(table: Self.databaseTableName, ifNotExists: true) { table in
            table.column("userID", .text)
                .notNull()
                .references(AppUserRecord.databaseTableName, column: "id", onDelete: .cascade)
            table.column("sourceID", .text).notNull()
            table.column("comicItemID", .text).notNull()
            table.column("comicTitle", .text).notNull()
            table.column("chapterID", .text)
            table.column("chapterKey", .text).notNull()
            table.column("chapterURL", .text)
            table.column("chapterTitle", .text).notNull()
            table.column("visitedAt", .datetime).notNull()
            table.column("coverURL", .text)
            table.column("lastReaderPageURL", .text)
            table.column("lastPageImageURL", .text)
            table.column("lastPageImageCacheKey", .text)
            table.column("lastPageIndex", .integer)
            table.column("previousChapterURL", .text)
            table.column("nextChapterURL", .text)
            table.column("sourceSnapshotJSON", .text)
            table.uniqueKey(["userID", "sourceID", "comicItemID", "chapterKey"])
        }
    }

    /// 中文注释：历史页按用户和访问时间倒序读取；sourceID 索引用于来源删除后的关联处理。
    static func createIndexes(in database: Database) throws {
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_comic_chapter_history_user_visited_at
            ON \(Self.databaseTableName)(userID, visitedAt DESC)
            """
        )
        try database.execute(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_comic_chapter_history_source
            ON \(Self.databaseTableName)(sourceID)
            """
        )
    }
}
