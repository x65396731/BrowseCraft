import Foundation

struct ReaderHistoryRestorePlan {
    let item: ContentItem
    let selectedChapter: ChapterLink?
    let lastPageIndex: Int?
    let lastPageImageURLString: String?
}

/// 中文注释：把漫画阅读历史还原为 Reader 初始输入；查询与导航补全不属于 Composition Factory。
struct PrepareReaderHistoryRestoreUseCase {
    private let repository: ComicChapterHistoryRepository

    init(repository: ComicChapterHistoryRepository) {
        self.repository = repository
    }

    func execute(history: ComicChapterHistory) -> ReaderHistoryRestorePlan {
        let storedChapterTitlesByURL: [String: String] = (try? self.repository.fetchHistory(userID: history.userID))?
            .filter { storedHistory in
                storedHistory.sourceID == history.sourceID
                    && storedHistory.comicItemID == history.comicItemID
            }
            .reduce(into: [:]) { titles, storedHistory in
                guard let chapterURL: String = storedHistory.chapterURL?.absoluteString else {
                    return
                }
                titles[chapterURL] = storedHistory.chapterTitle
            } ?? [:]
        let readerURL: URL? = history.lastReaderPageURL ?? history.chapterURL
        let item: ContentItem = ContentItem(
            id: history.comicItemID,
            sourceId: history.sourceID,
            title: history.comicTitle,
            detailURL: readerURL?.absoluteString ?? history.comicItemID,
            coverURL: history.coverURL?.absoluteString,
            type: .comic,
            latestText: history.chapterTitle,
            updatedAt: history.visitedAt
        )
        let selectedChapter: ChapterLink? = readerURL.map { url in
            var navigationChapterURLs: [String] = []
            var navigationChapterTitles: [String?] = []
            let appendNavigationChapter: (URL?, String?) -> Void = { chapterURL, storedTitle in
                guard let chapterURL: URL else {
                    return
                }
                navigationChapterURLs.append(chapterURL.absoluteString)
                navigationChapterTitles.append(
                    storedTitle ?? storedChapterTitlesByURL[chapterURL.absoluteString]
                )
            }
            appendNavigationChapter(history.nextChapterURL, history.nextChapterTitle)
            appendNavigationChapter(url, history.chapterTitle)
            appendNavigationChapter(history.previousChapterURL, history.previousChapterTitle)
            return ChapterLink(
                title: history.chapterTitle,
                url: url.absoluteString,
                navigationChapterURLs: navigationChapterURLs,
                navigationChapterTitles: navigationChapterTitles
            )
        }

        return ReaderHistoryRestorePlan(
            item: item,
            selectedChapter: selectedChapter,
            lastPageIndex: history.lastPageIndex,
            lastPageImageURLString: history.lastPageImageURL?.absoluteString
        )
    }
}
