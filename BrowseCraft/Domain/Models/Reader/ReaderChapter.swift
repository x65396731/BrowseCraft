import Foundation

// 中文注释：ReaderChapter 是阅读器渲染章节页面时使用的标准化章节内容。

/// 中文注释：标准化的阅读页解析结果。
/// 中文注释：它表示某一章的阅读内容，上层不需要关心来源是 HTML、JSON 还是其他格式。
struct ReaderChapter: Hashable {
    var sourceId: String
    var comicTitle: String?
    var chapterTitle: String?
    var chapterURL: String
    var catalogURL: String?
    var previousChapterURL: String?
    var nextChapterURL: String?
    var pageImageURLs: [String]
    var pageImageHeaders: [String: [String: String]] = [:]
}
