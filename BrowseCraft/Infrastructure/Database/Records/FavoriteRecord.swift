import Foundation
import GRDB

// 中文注释：FavoriteRecord 保存当前用户收藏过的内容 ID。

/// 中文注释：收藏表暂时仍沿用 itemId，后续用户维度历史表会单独补充 userID。
struct FavoriteRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "favorites"

    var itemId: String
    var createdAt: Date
}
