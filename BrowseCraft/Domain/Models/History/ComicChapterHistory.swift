import Foundation

// 中文注释：ComicChapterHistory 保存用户实际阅读过的漫画章节。

/// 中文注释：一条记录对应某部漫画的某一话/章节，例如第 100 话，而不是整部漫画列表项。
struct ComicChapterHistory: Identifiable, Hashable {
    var id: String {
        return [
            self.userID,
            self.sourceID,
            self.comicItemID,
            self.chapterKey
        ].joined(separator: "::")
    }

    var userID: String
    var sourceID: String
    var comicItemID: String
    var comicTitle: String
    var chapterID: String?
    /// 中文注释：chapterKey 是章节历史的稳定身份，优先由 chapterID 生成，否则由 chapterURL 生成。
    var chapterKey: String
    /// 中文注释：chapterURL 强烈推荐保存；部分来源没有稳定 URL 时允许为空，但 chapterKey 仍必须非空。
    var chapterURL: URL?
    var chapterTitle: String
    var visitedAt: Date
    var coverURL: URL?
    var lastPageImageURL: URL?
    var lastPageImageCacheKey: String?
    var lastPageIndex: Int?
}
