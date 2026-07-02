import Foundation

// 中文注释：SiteRule.swift 属于领域模型层，用于说明本文件承载的核心职责。

/// 中文注释：站点规则描述 BrowseCraft 如何从某个源站抽取内容。
/// 中文注释：它属于领域数据，不关心底层使用 SwiftSoup、JSON 解析器还是其他解析器。
struct SiteRule: Codable, Hashable {
    /// 中文注释：V2 规则版本号；旧版扁平规则未提供时按旧解析链路处理。
    var version: Int?
    /// 中文注释：站点级配置，承载域名、语言、展示模式等非抽取字段。
    var site: SiteConfig?
    /// 中文注释：站点常见 URL 形态，用于识别列表、详情、阅读页和搜索页。
    var urlPatterns: URLPatterns?
    /// 中文注释：V2 页面入口定义；用于描述首页、分类、搜索、详情和阅读页之间的关系。
    var pages: [PageRule]?
    /// 中文注释：V2 规则集合；新规则优先放这里，旧字段保留用于兼容。
    var ruleSets: RuleSets?
    /// 中文注释：站点级请求配置，页面和规则可覆盖。
    var sharedRequest: RequestConfig?
    var flags: [SiteFlag]?
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
    var id: String?
    var url: String
    /// 中文注释：V2 列表整体说明文本，例如 Pepper&Carrot 归档页的系列简介。
    var text: ExtractRule?
    var item: String
    /// 中文注释：V2 列表项规则；存在时可替代旧版 item 字符串。
    var itemRule: ExtractRule?
    /// 中文注释：V2 列表字段集合，支持发布日期、作者、分类等扩展字段。
    var fields: ListFields?
    var title: String
    var link: String
    var cover: String?
    var type: ContentType
    var latestText: String?
    var pagination: PaginationRule?
    var ready: ExtractRule?
    var request: RequestConfig?
    var js: String?
}

/// 中文注释：ListTabRule 表示首页或列表页顶部的分类入口。
struct ListTabRule: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var list: ListRule
}

/// 中文注释：DetailRule 是 struct，负责本模块中的对应职责。
struct DetailRule: Codable, Hashable {
    var id: String?
    /// 中文注释：V2 详情字段集合，用于表达标题、封面、简介、作者、标签等详情信息。
    var fields: DetailFields?
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
    /// 中文注释：列表项本身就是阅读页时，跳过详情页章节抽取，直接把 detailURL 当作章节 URL。
    var treatDetailURLAsChapter: Bool?
    var tagRule: NestedItemRule?
    var pictureRule: PictureRule?
    var commentRule: NestedItemRule?
    var ready: ExtractRule?
    var request: RequestConfig?
    var js: String?
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

/// 中文注释：站点级静态配置，不直接参与 DOM 抽取。
struct SiteConfig: Codable, Hashable {
    var name: String
    var domain: String
    var baseURL: String
    var iconURL: String?
    var displayMode: DisplayMode?
    var loginURL: String?
    var language: String?
}

/// 中文注释：站点 URL 模式集合，用于路由识别和规则调试。
struct URLPatterns: Codable, Hashable {
    var series: String?
    var list: String?
    var detail: String?
    var gallery: String?
    var search: String?
}

struct PageRule: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var type: PageType
    var url: String?
    var displayMode: DisplayMode?
    var request: RequestConfig?
    var ruleRefs: RuleRefs?
    var flags: [PageFlag]?
}

enum PageType: String, Codable, Hashable {
    case home
    case series
    case list
    case category
    case detail
    case gallery
    case search
    case reader
}

enum DisplayMode: String, Codable, Hashable {
    case list
    case grid
    case webcomic
    case verticalReader
    case pagedReader
}

struct RuleRefs: Codable, Hashable {
    var series: String?
    var list: String?
    var detail: String?
    var gallery: String?
    var search: String?
}

struct RuleSets: Codable, Hashable {
    var seriesRules: [ListRule]?
    var listRules: [ListRule]?
    var detailRules: [DetailRule]?
    var galleryRules: [GalleryRule]?
    var searchRules: [SearchRule]?
}

enum SiteFlag: String, Codable, Hashable {
    case staticHTML
    case multilingual
    case openContent
    case needsWebView
}

enum PageFlag: String, Codable, Hashable {
    case lazyImages
    case hasQualityVariants
    case hasNavigationLinks
}

/// 中文注释：V2 列表标准字段；Pepper&Carrot 这类归档页可提供 publishedAt 和 description。
struct ListFields: Codable, Hashable {
    var idCode: ExtractRule?
    var title: ExtractRule
    var cover: ExtractRule?
    var detailURL: ExtractRule
    var latestText: ExtractRule?
    var description: ExtractRule?
    var coverWidth: ExtractRule?
    var coverHeight: ExtractRule?
    var category: ExtractRule?
    var author: ExtractRule?
    var publishedAt: ExtractRule?
    var rating: ExtractRule?
    var totalImages: ExtractRule?
    var language: ExtractRule?
}

/// 中文注释：V2 详情标准字段；用于承载系列简介、作者、状态、语言和版权信息。
struct DetailFields: Codable, Hashable {
    var idCode: ExtractRule?
    var title: ExtractRule?
    var cover: ExtractRule?
    var description: ExtractRule?
    var author: ExtractRule?
    var status: ExtractRule?
    var category: ExtractRule?
    var tags: ExtractRule?
    var language: ExtractRule?
    var publishedAt: ExtractRule?
    var updatedAt: ExtractRule?
    var license: ExtractRule?
}

/// 中文注释：通用嵌套列表规则，可用于标签、评论、相关链接等重复结构。
struct NestedItemRule: Codable, Hashable {
    var section: SectionRule?
    var item: ExtractRule
    var idCode: ExtractRule?
    var title: ExtractRule?
    var url: ExtractRule?
    var text: ExtractRule?
    var datetime: ExtractRule?
}

/// 中文注释：图片或媒体资源规则；详情页插图、相关图、视频封面可复用。
struct PictureRule: Codable, Hashable {
    var section: SectionRule?
    var item: ExtractRule
    var image: ExtractRule
    var thumbnail: ExtractRule?
    var link: ExtractRule?
    var title: ExtractRule?
    var width: ExtractRule?
    var height: ExtractRule?
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
    var language: ExtractRule?
    var index: ExtractRule?
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
    var id: String?
    /// 中文注释：阅读页主作用域，例如 Pepper&Carrot 的 .container.webcomic。
    var mainScope: ExtractRule?
    /// 中文注释：V2 页图节点规则；存在时可替代旧版 imageItem 字符串。
    var item: ExtractRule?
    /// 中文注释：V2 页图 URL 抽取规则；存在时可替代旧版 imageUrl 字符串。
    var image: ExtractRule?
    var thumbnail: ExtractRule?
    var link: ExtractRule?
    var totalPages: ExtractRule?
    var secondLevelPageURL: ExtractRule?
    /// 中文注释：阅读页质量/模式切换入口，例如普通、高清、双语对照。
    var variants: [GalleryVariantRule]?
    /// 中文注释：源文件、制作包、相关下载等资源链接，不直接作为阅读图片。
    var sourceFiles: [ResourceLinkRule]?
    var pagination: PaginationRule?
    var request: RequestConfig?
    var js: String?
    var imageItem: String
    var imageUrl: String
    var comicTitle: String?
    var chapterTitle: String?
    var catalogLink: String?
    var previousLink: String?
    var nextLink: String?
}

struct GalleryVariantRule: Codable, Hashable {
    var id: String
    var title: String?
    var url: ExtractRule
    var isDefault: Bool?
}

struct ResourceLinkRule: Codable, Hashable {
    var id: String?
    var title: ExtractRule?
    var url: ExtractRule
    var fileType: ExtractRule?
    var fileSize: ExtractRule?
}

struct SearchRule: Codable, Hashable {
    var id: String?
    var keywordEncoding: KeywordEncoding?
    var url: String
    var method: HTTPMethod?
    var request: RequestConfig?
    var listRuleRef: String?
    var item: ExtractRule
    var fields: ListFields
    var pagination: PaginationRule?
}

enum KeywordEncoding: String, Codable, Hashable {
    case urlQueryAllowed
    case percentEncoded
    case raw
}

struct PaginationRule: Codable, Hashable {
    var nextPage: ExtractRule?
    var pagePlaceholder: String?
    var maxPages: Int?
    var stopWhenEmpty: Bool?
}

struct RequestConfig: Codable, Hashable {
    var method: HTTPMethod?
    var headers: [String: String]?
    var body: RequestBody?
    var cookiePolicy: CookiePolicy?
    var charset: Charset?
    var needsWebView: Bool?
    var autoScroll: Bool?
    var imageHeaders: [String: String]?
}

enum HTTPMethod: String, Codable, Hashable {
    case get = "GET"
    case post = "POST"
}

struct RequestBody: Codable, Hashable {
    var contentType: String?
    var value: String
}

enum CookiePolicy: String, Codable, Hashable {
    case none
    case browser
    case custom
    case browserThenCustom
}

enum Charset: String, Codable, Hashable {
    case utf8
    case gb18030
    case shiftJIS
    case auto
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
