import Foundation

// 中文注释：Source 列表读写用例，供来源管理、书架和历史页面读取本地 Source 状态。

/// 中文注释：从本地存储加载所有内容源，包括内置源和用户添加的源。
struct LoadSourcesUseCase {
    private let sourceRepository: SourceRepository

    init(sourceRepository: SourceRepository) {
        self.sourceRepository = sourceRepository
    }

    func execute() throws -> [Source] {
        return try self.sourceRepository.fetchSources()
    }
}

/// 中文注释：从本地存储删除一个 Source；当前由 Sources 页面侧滑删除触发。
struct DeleteSourceUseCase {
    private let sourceRepository: SourceRepository

    init(sourceRepository: SourceRepository) {
        self.sourceRepository = sourceRepository
    }

    func execute(sourceId: String) throws {
        try self.sourceRepository.deleteSource(id: sourceId)
    }
}
