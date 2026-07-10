import Foundation
import GRDB

// 中文注释：UserLibraryStateRecord 是 user_library_state 表的一行。

/// 中文注释：listContextJSON 只保存 source 内部列表上下文，不保存列表 items。
struct UserLibraryStateRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "user_library_state"

    var userID: String
    var selectedSourceID: String?
    var listContextJSON: String?
    var lastRefreshAt: Date?
    var updatedAt: Date

    init(state: UserLibraryState) throws {
        self.userID = state.userID
        self.selectedSourceID = state.selectedSourceID
        self.listContextJSON = try Self.encodeListContext(state.listContext)
        self.lastRefreshAt = state.lastRefreshAt
        self.updatedAt = state.updatedAt
    }

    func domainModel() -> UserLibraryState {
        return UserLibraryState(
            userID: self.userID,
            selectedSourceID: self.selectedSourceID,
            listContext: Self.decodeListContext(self.listContextJSON),
            lastRefreshAt: self.lastRefreshAt,
            updatedAt: self.updatedAt
        )
    }

    private static func encodeListContext(_ context: ListContext?) throws -> String? {
        guard let context: ListContext = context else {
            return nil
        }

        let data: Data = try JSONEncoder().encode(context)
        return String(data: data, encoding: .utf8)
    }

    private static func decodeListContext(_ json: String?) -> ListContext? {
        guard let json: String = json,
              let data: Data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(ListContext.self, from: data)
    }
}
