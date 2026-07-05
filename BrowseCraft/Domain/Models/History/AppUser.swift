import Foundation

// 中文注释：AppUser 是本地数据库历史记录的用户根模型。

/// 中文注释：当前 MVP 可以只有本地默认用户，但历史表必须显式挂到 userID 下。
struct AppUser: Identifiable, Hashable {
    static let localDefaultID: String = "local.default"

    var id: String
    var displayName: String?
    var createdAt: Date
    var updatedAt: Date
}
