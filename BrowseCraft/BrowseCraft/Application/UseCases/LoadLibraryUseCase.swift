import Foundation

// 中文注释：LoadLibraryUseCase.swift 属于应用用例层，用于说明本文件承载的核心职责。

/// 中文注释：加载 Library 页面需要展示的内容条目。
struct LoadLibraryUseCase {
    private let contentRepository: ContentRepository

    init(contentRepository: ContentRepository) {
        self.contentRepository = contentRepository
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute(sourceId: String? = nil) throws -> [ContentItem] {
        return try self.contentRepository.fetchItems(sourceId: sourceId)
    }
}

