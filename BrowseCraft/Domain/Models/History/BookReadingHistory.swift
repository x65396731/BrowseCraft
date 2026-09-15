import BrowseCraftDomain
import Foundation

// 中文注释：BookReadingHistory 保存用户读过的站点书（规则来源里的一部作品）。

/// 中文注释：一本书一条（与漫画按作品聚合后的历史行同形），记最后读到的章节；续读位置在 book_reading_progress，这里不重复存 Locator。
/// 本地导入书的入口已藏起（Documentation/Book/Local-Book-Import-Design.md 第八节），不进历史。
struct BookReadingHistory: Identifiable, Hashable, Sendable {
    var id: String {
        return [
            self.userID,
            self.sourceID,
            self.detailURL
        ].joined(separator: "::")
    }

    var userID: String
    var sourceID: String
    /// 中文注释：作品地址是站点书的稳定身份（`SiteBookIdentity` 同样由 sourceID + 作品地址派生）。
    var detailURL: String
    var bookItemID: String
    var bookTitle: String
    var coverURL: URL?
    var chapterTitle: String?
    var chapterURL: URL?
    var visitedAt: Date
    var sourceSnapshot: SourceSnapshot? = nil

    func fallbackSource() -> Source? {
        return self.sourceSnapshot?.source()
    }
}
