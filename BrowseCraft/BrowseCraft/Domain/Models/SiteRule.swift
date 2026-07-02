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
    /// 中文注释：详情页主内容作用域，用于把章节解析限制在作品正文附近。
    var mainScope: ExtractRule?
    /// 中文注释：从主作用域中排除排行、推荐、广告等公共区域。
    var exclude: [ExtractRule]?
    /// 中文注释：V2 章节子规则；存在时优先于下方旧版 chapterContainer/chapterItem 字段。
    var chapterRule: ChapterRule?
    var chapterContainer: String?
    var chapterItem: String?
    var chapterTitle: String?
    var chapterLink: String?
}

/// 中文注释：ExtractRule 表示一次结构化抽取，替代旧版 selector@attr 字符串。
struct ExtractRule: Codable, Hashable {
    var selector: String?
    var function: ExtractFunction
    var param: String?
    var regex: String?
    var replacement: String?
    var fallback: [ExtractRule]?
}

enum ExtractFunction: String, Codable, Hashable {
    case text
    case html
    case attr
    case raw
    case url
}

struct SectionRule: Codable, Hashable {
    var id: String?
    var title: ExtractRule?
    var role: SectionRole?
    var itemLayout: ItemLayout?
    /// 中文注释：Section 的容器节点。章节解析会按容器顺序保留源站分组顺序。
    var container: ExtractRule
    var itemRuleRef: String?
    var listRuleRef: String?
    var exclude: [ExtractRule]?
}

enum SectionRole: String, Codable, Hashable {
    case main
    case ranking
    case recommendation
    case category
}

enum ItemLayout: String, Codable, Hashable {
    case horizontalRow
    case verticalGrid
}

struct ChapterRule: Codable, Hashable {
    var section: SectionRule?
    var item: ExtractRule
    /// 中文注释：章节稳定标识抽取规则；可从结构化数据中读取 id 并拼出章节 URL。
    var idCode: ExtractRule?
    var title: ExtractRule
    var url: ExtractRule
    var datetime: ExtractRule?
    var sort: ChapterSort?
    /// 中文注释：预留字段，用于要求章节组必须包含列表卡片上的 latestText，避免匹配到推荐区。
    var mustMatchLatestText: Bool?
}

enum ChapterSort: String, Codable, Hashable {
    case ascending
    case descending
    case none
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
