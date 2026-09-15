import BrowseCraftDomain
import Foundation

// 中文注释：阅读器读的是「一本书」：本地导入的（LocalBook）或规则来源里的一部作品（站点书）。两者共用阅读器、进度与书签。

struct SiteBookChapterSelection: Hashable, Sendable {
    let source: Source
    let item: ContentItem
    /// 中文注释：点开的章节；nil 表示从续读位置或第一章开始。
    let chapterURL: URL?
    let chapterTitle: String?
}

extension SiteBookChapterSelection {
    /// 中文注释：从历史重开：作品身份（sourceID + 作品地址）与当初一致，续读位置与书签才接得上；不带章节，阅读器按续读位置接着读。
    init(history: BookReadingHistory, source: Source) {
        self.init(
            source: source,
            item: ContentItem(
                id: history.bookItemID,
                sourceId: history.sourceID,
                title: history.bookTitle,
                detailURL: history.detailURL,
                coverURL: history.coverURL?.absoluteString,
                type: .article
            ),
            chapterURL: nil,
            chapterTitle: nil
        )
    }
}

enum BookReaderSubject: Hashable, Sendable {
    case local(LocalBook)
    case site(SiteBookChapterSelection)

    var bookID: UUID {
        switch self {
        case .local(let book):
            return book.id
        case .site(let selection):
            return SiteBookIdentity.bookID(sourceID: selection.source.id, detailURL: selection.item.detailURL)
        }
    }

    var title: String {
        switch self {
        case .local(let book):
            return book.title
        case .site(let selection):
            return selection.item.title
        }
    }
}
