@preconcurrency import GRDB

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
}
