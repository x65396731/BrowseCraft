import Foundation

// 中文注释：LoadSourcesUseCase.swift 属于应用用例层，用于说明本文件承载的核心职责。

/// 中文注释：加载所有用户配置的内容源。
struct LoadSourcesUseCase {
    private let sourceRepository: SourceRepository

    init(sourceRepository: SourceRepository) {
        self.sourceRepository = sourceRepository
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute() throws -> [Source] {
        return try self.sourceRepository.fetchSources()
    }
}

/// 中文注释：从本地存储删除一个源规则。
struct DeleteSourceUseCase {
    private let sourceRepository: SourceRepository

    init(sourceRepository: SourceRepository) {
        self.sourceRepository = sourceRepository
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute(sourceId: String) throws {
        try self.sourceRepository.deleteSource(id: sourceId)
    }
}
