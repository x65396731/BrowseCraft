import Foundation

// 中文注释：SiteRule.swift 属于领域模型层，用于说明本文件承载的核心职责。

/// 中文注释：站点规则描述 BrowseCraft 如何从某个源站抽取内容。
/// 中文注释：它属于领域数据，不关心底层使用 SwiftSoup、JSON 解析器还是其他解析器。
struct SiteRule: Codable, Hashable {
    var name: String
    var baseUrl: String
    var list: ListRule
    var listTabs: [ListTabRule]?
    var detail: DetailRule?
    var gallery: GalleryRule?
    var video: VideoRule?

    var availableListTabs: [ListTabRule] {
        if let listTabs: [ListTabRule] = self.listTabs, listTabs.isEmpty == false {
            return listTabs
        }

        return [
            ListTabRule(
                id: "default",
                title: "发现",
                list: self.list
            )
        ]
    }
}

/// 中文注释：ListRule 是 struct，负责本模块中的对应职责。
struct ListRule: Codable, Hashable {
    var url: String
    var item: String
    var title: String
    var link: String
    var cover: String?
    var type: ContentType
    var latestText: String?
}

/// 中文注释：ListTabRule 表示首页或列表页顶部的分类入口。
struct ListTabRule: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var list: ListRule
}

/// 中文注释：DetailRule 是 struct，负责本模块中的对应职责。
struct DetailRule: Codable, Hashable {
    var title: String?
    var cover: String?
    var chapterContainer: String?
    var chapterItem: String?
    var chapterTitle: String?
    var chapterLink: String?
}

/// 中文注释：GalleryRule 是 struct，负责本模块中的对应职责。
struct GalleryRule: Codable, Hashable {
    var imageItem: String
    var imageUrl: String
    var comicTitle: String?
    var chapterTitle: String?
    var catalogLink: String?
    var previousLink: String?
    var nextLink: String?
}

/// 中文注释：VideoRule 是 struct，负责本模块中的对应职责。
struct VideoRule: Codable, Hashable {
    var videoUrl: String
}

extension SiteRule {
    /// 中文注释：AddSourceView 展示给用户参考的规则 JSON 示例。
    static let exampleJSON: String = """
    {
      "name": "Example Site",
      "baseUrl": "https://example.com",
      "list": {
        "url": "https://example.com/list/{page}",
        "item": ".card",
        "title": ".title",
        "link": ".title@href",
        "cover": "img@src",
        "type": "comic",
        "latestText": ".badge"
      },
      "detail": {
        "title": "h1",
        "cover": ".cover img@src",
        "chapterContainer": ".chapter-list",
        "chapterItem": ".chapter-list a",
        "chapterTitle": "this",
        "chapterLink": "this@href"
      },
      "gallery": {
        "imageItem": ".reader img",
        "imageUrl": "this@src"
      },
      "video": {
        "videoUrl": "video@src"
      }
    }
    """

    /// Built-in production rules live in the private BrowseCraftRulesKit package.
    /// Keep this public example generic so the app shell can be published safely.
}
