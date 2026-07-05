import Foundation
import GRDB

// 中文注释：AppUserRecord 是 users 表的一行。

/// 中文注释：当前只保存本地用户根信息，后续历史表通过 userID 关联到它。
struct AppUserRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "users"

    var id: String
    var displayName: String?
    var createdAt: Date
    var updatedAt: Date

    init(user: AppUser) {
        self.id = user.id
        self.displayName = user.displayName
        self.createdAt = user.createdAt
        self.updatedAt = user.updatedAt
    }

    func domainModel() -> AppUser {
        return AppUser(
            id: self.id,
            displayName: self.displayName,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt
        )
    }
}
