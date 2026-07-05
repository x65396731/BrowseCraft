import Foundation

// 中文注释：ReadingHistoryUseCases 承接新的 RSS/漫画历史保存与读取用例。

/// 中文注释：保存 RSS 详情页历史；具体触发点会在 RSS 详情页接入小节处理。
struct SaveRSSReadingHistoryUseCase {
    private let repository: RSSReadingHistoryRepository

    init(repository: RSSReadingHistoryRepository) {
        self.repository = repository
    }

    func execute(history: RSSReadingHistory) throws {
        try self.repository.save(history)
    }
}

/// 中文注释：保存漫画章节阅读历史；具体触发点会在 Reader 接入小节处理。
struct SaveComicChapterHistoryUseCase {
    private let repository: ComicChapterHistoryRepository

    init(repository: ComicChapterHistoryRepository) {
        self.repository = repository
    }

    func execute(history: ComicChapterHistory) throws {
        try self.repository.save(history)
    }
}

/// 中文注释：聚合 RSS 和漫画历史，供未来 History 页面按访问时间倒序展示。
struct LoadReadingHistoryEntriesUseCase {
    private let rssRepository: RSSReadingHistoryRepository
    private let comicRepository: ComicChapterHistoryRepository

    init(
        rssRepository: RSSReadingHistoryRepository,
        comicRepository: ComicChapterHistoryRepository
    ) {
        self.rssRepository = rssRepository
        self.comicRepository = comicRepository
    }

    func execute(userID: String) throws -> [ReadingHistoryEntry] {
        let rssEntries: [ReadingHistoryEntry] = try self.rssRepository
            .fetchHistory(userID: userID)
            .map { history in
                return ReadingHistoryEntry(rssHistory: history)
            }
        let comicEntries: [ReadingHistoryEntry] = try self.comicRepository
            .fetchHistory(userID: userID)
            .map { history in
                return ReadingHistoryEntry(comicHistory: history)
            }

        return (rssEntries + comicEntries).sorted { lhs, rhs in
            return lhs.visitedAt > rhs.visitedAt
        }
    }
}
