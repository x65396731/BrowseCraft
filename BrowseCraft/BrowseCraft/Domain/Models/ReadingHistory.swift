import Foundation

// 中文注释：ReadingHistory.swift 属于领域模型层，用于说明本文件承载的核心职责。

/// 中文注释：漫画、图集和文章的阅读进度模型。
/// 中文注释：视频进度需要 currentTime 和 duration，后续会单独建模。
struct ReadingHistory: Identifiable, Hashable {
    var id: String {
        return self.itemId
    }

    var itemId: String
    var chapterId: String?
    var pageIndex: Int
    var updatedAt: Date
}

