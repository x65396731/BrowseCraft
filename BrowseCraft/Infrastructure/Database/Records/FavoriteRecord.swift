import Foundation
import GRDB

// 中文注释：FavoriteRecord 是 favorites 表的一行，按 userID 聚合收藏集合。

struct FavoriteRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "favorites"

    var userID: String
    var favoriteItemIDsJSON: String
    var favoriteItemsJSON: String
    var rssFavoritesJSON: String?
    var comicFavoritesJSON: String?
    var videoFavoritesJSON: String?
    var createdAt: Date
    var updatedAt: Date
}
