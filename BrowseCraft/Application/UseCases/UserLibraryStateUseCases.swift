import Foundation

// 中文注释：UserLibraryStateUseCases 承接 Library 启动状态的读取和保存。

struct LoadUserLibraryStateUseCase {
    private let repository: UserLibraryStateRepository

    init(repository: UserLibraryStateRepository) {
        self.repository = repository
    }

    func execute(userID: String) throws -> UserLibraryState? {
        return try self.repository.fetch(userID: userID)
    }
}

struct SaveUserLibraryStateUseCase {
    private let repository: UserLibraryStateRepository

    init(repository: UserLibraryStateRepository) {
        self.repository = repository
    }

    func execute(state: UserLibraryState) throws {
        try self.repository.save(state)
    }
}
