import Foundation
import BrowseCraftCore

// 中文注释：ReaderChapter 是阅读器渲染章节页面时使用的标准化章节内容。

enum ReaderPageResource: Hashable {
    case remoteImageURL(String)
    case protectedResource(ProtectedReaderImageReference)

    var displayURLString: String {
        switch self {
        case .remoteImageURL(let urlString):
            return urlString
        case .protectedResource(let reference):
            return reference.displayURLString
        }
    }
}

struct ProtectedReaderImageReference: Hashable {
    var displayURLString: String
    var sourceID: String
    var baseURL: URL?
    var rule: ProtectedResourceRule
    var parameters: [String: String]
}

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
    var pageResources: [ReaderPageResource] = []
    var pageImageHeaders: [String: [String: String]] = [:]
}
