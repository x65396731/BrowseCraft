import Foundation

// 中文注释：HistoryRepository.swift 属于仓储协议层，用于说明本文件承载的核心职责。

/// 中文注释：阅读历史仓储协议，定义历史记录的读取和保存能力。
protocol HistoryRepository {
    /// 中文注释：fetchReadingHistory 方法封装当前类型的一段业务或界面行为。
    func fetchReadingHistory() throws -> [ReadingHistory]
    /// 中文注释：saveReadingHistory 方法封装当前类型的一段业务或界面行为。
    func saveReadingHistory(_ history: ReadingHistory) throws
}

