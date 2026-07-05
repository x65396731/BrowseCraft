import Foundation

// 中文注释：UserLibraryStateRepository 负责用户 Library 启动状态的持久化读写。

protocol UserLibraryStateRepository {
    func fetch(userID: String) throws -> UserLibraryState?
    func save(_ state: UserLibraryState) throws
}
