import Foundation
import GRDB

struct FavoriteRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "favorites"

    var itemId: String
    var createdAt: Date
}

