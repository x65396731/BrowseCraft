import Foundation

// 中文注释：ComicChapterHistoryRepository 负责漫画章节级阅读历史的持久化读写。

/// 中文注释：保存语义必须是 upsert，同一用户同一章节再次阅读时更新旧进度。
protocol ComicChapterHistoryRepository: Sendable {
    func save(_ history: ComicChapterHistory) throws
    func fetchHistory(userID: String) throws -> [ComicChapterHistory]
    func fetchLatest(
        userID: String,
        sourceID: String,
        comicItemID: String
    ) throws -> ComicChapterHistory?
    /// 中文注释：本作品读过的全部章节，最近的在前；默认实现从全量历史里筛，GRDB 实现按唯一键前三列查。
    func fetchHistory(
        userID: String,
        sourceID: String,
        comicItemID: String
    ) throws -> [ComicChapterHistory]
    func delete(_ history: ComicChapterHistory) throws
    /// 中文注释：批量删除；实现应在一个事务内完成，默认实现逐条调用 delete。
    func delete(_ histories: [ComicChapterHistory]) throws
}

extension ComicChapterHistoryRepository {
    func fetchHistory(
        userID: String,
        sourceID: String,
        comicItemID: String
    ) throws -> [ComicChapterHistory] {
        return try self.fetchHistory(userID: userID).filter { history in
            return history.sourceID == sourceID && history.comicItemID == comicItemID
        }
    }

    func delete(_ histories: [ComicChapterHistory]) throws {
        for history: ComicChapterHistory in histories {
            try self.delete(history)
        }
    }
}
