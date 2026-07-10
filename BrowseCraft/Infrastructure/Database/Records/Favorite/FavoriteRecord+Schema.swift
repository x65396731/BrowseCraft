import GRDB

extension FavoriteRecord {
    enum Columns {
        static let userID: Column = Column("userID")
        static let favoriteItemIDsJSON: Column = Column("favoriteItemIDsJSON")
        static let favoriteItemsJSON: Column = Column("favoriteItemsJSON")
        static let rssFavoritesJSON: Column = Column("rssFavoritesJSON")
        static let comicFavoritesJSON: Column = Column("comicFavoritesJSON")
        static let videoFavoritesJSON: Column = Column("videoFavoritesJSON")
        static let createdAt: Column = Column("createdAt")
        static let updatedAt: Column = Column("updatedAt")
        static let deletedAt: Column = Column("deletedAt")
    }

    /// 中文注释：favorites 按 userID 聚合收藏快照，当前不拆成每条收藏一行。
    /// 中文注释：deletedAt 为未来整组收藏云端删除或重置预留。
    static func createTable(in database: Database) throws {
        try database.create(table: Self.databaseTableName, ifNotExists: true) { table in
            table.column("userID", .text)
                .primaryKey()
                .references(AppUserRecord.databaseTableName, column: "id", onDelete: .cascade)
            table.column("favoriteItemIDsJSON", .text).notNull()
            table.column("favoriteItemsJSON", .text).notNull()
            table.column("rssFavoritesJSON", .text)
            table.column("comicFavoritesJSON", .text)
            table.column("videoFavoritesJSON", .text)
            table.column("createdAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("deletedAt", .datetime)
        }
    }

    /// 中文注释：当前收藏读取按主键 userID 命中，不需要额外索引。
    static func createIndexes(in database: Database) throws {
        _ = database
    }
}
