import Foundation

// 中文注释：ComicChapterHistoryRepository 负责漫画章节级阅读历史的持久化读写。

/// 中文注释：保存语义必须是 upsert，同一用户同一章节再次阅读时更新旧进度。
protocol ComicChapterHistoryRepository {
    func save(_ history: ComicChapterHistory) throws
    func fetchHistory(userID: String) throws -> [ComicChapterHistory]
    func fetchLatest(
        userID: String,
        sourceID: String,
        comicItemID: String
    ) throws -> ComicChapterHistory?
    func delete(_ history: ComicChapterHistory) throws
}
