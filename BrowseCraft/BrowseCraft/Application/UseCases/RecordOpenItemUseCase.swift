import Foundation

// 中文注释：RecordOpenItemUseCase.swift 属于应用用例层，用于说明本文件承载的核心职责。

/// 中文注释：记录用户打开过某个内容条目。
/// 中文注释：这是阅读历史的基础版本，为后续更完整的阅读进度做铺垫。
struct RecordOpenItemUseCase {
    private let historyRepository: HistoryRepository

    init(historyRepository: HistoryRepository) {
        self.historyRepository = historyRepository
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute(itemId: String) throws {
        let history: ReadingHistory = ReadingHistory(
            itemId: itemId,
            chapterId: nil,
            pageIndex: 0,
            updatedAt: Date()
        )

        try self.historyRepository.saveReadingHistory(history)
    }
}

