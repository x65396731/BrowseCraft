import Foundation

// 中文注释：UserLibraryState 保存用户启动时 Library 应恢复的当前请求入口。

/// 中文注释：该模型只保存 source 和列表上下文，不保存 Library 列表 items。
struct UserLibraryState: Identifiable, Hashable {
    var id: String {
        return self.userID
    }

    var userID: String
    var selectedSourceID: String?
    var listContext: ListContext?
    var lastRefreshAt: Date?
    var updatedAt: Date
}
