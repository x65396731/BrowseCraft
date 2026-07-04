import Foundation
import BrowseCraftCore

// 中文注释：App 侧 Core rule typealias 入口；真实规则模型定义在 BrowseCraftCore。

typealias SiteRule = BrowseCraftCore.SiteRule
typealias ListRule = BrowseCraftCore.ListRule
typealias ListTabRule = BrowseCraftCore.ListTabRule
typealias ListContext = BrowseCraftCore.ListContext
typealias TabGroupRule = BrowseCraftCore.TabGroupRule
typealias TabRule = BrowseCraftCore.TabRule
typealias TabLayout = BrowseCraftCore.TabLayout
typealias DetailRule = BrowseCraftCore.DetailRule
typealias ExtractRule = BrowseCraftCore.ExtractRule
typealias SelectorKind = BrowseCraftCore.SelectorKind
typealias ExtractFunction = BrowseCraftCore.ExtractFunction
typealias SectionRule = BrowseCraftCore.SectionRule
typealias SiteConfig = BrowseCraftCore.SiteConfig
typealias URLPatterns = BrowseCraftCore.URLPatterns
typealias URLTemplateRule = BrowseCraftCore.URLTemplateRule
typealias URLPlaceholderRule = BrowseCraftCore.URLPlaceholderRule
typealias URLPlaceholderKind = BrowseCraftCore.URLPlaceholderKind
typealias PageRule = BrowseCraftCore.PageRule
typealias PageType = BrowseCraftCore.PageType
typealias DisplayMode = BrowseCraftCore.DisplayMode
typealias RuleRefs = BrowseCraftCore.RuleRefs
typealias RuleSets = BrowseCraftCore.RuleSets
typealias SiteFlag = BrowseCraftCore.SiteFlag
typealias PageFlag = BrowseCraftCore.PageFlag
typealias ListFields = BrowseCraftCore.ListFields
typealias DetailFields = BrowseCraftCore.DetailFields
typealias NestedItemRule = BrowseCraftCore.NestedItemRule
typealias TagRule = BrowseCraftCore.TagRule
typealias CommentRule = BrowseCraftCore.CommentRule
typealias PictureRule = BrowseCraftCore.PictureRule
typealias SectionRole = BrowseCraftCore.SectionRole
typealias ItemLayout = BrowseCraftCore.ItemLayout
typealias ChapterRule = BrowseCraftCore.ChapterRule
typealias ChapterSort = BrowseCraftCore.ChapterSort
typealias GalleryRule = BrowseCraftCore.GalleryRule
typealias GalleryVariantRule = BrowseCraftCore.GalleryVariantRule
typealias ResourceLinkRule = BrowseCraftCore.ResourceLinkRule
typealias SearchRule = BrowseCraftCore.SearchRule
typealias KeywordEncoding = BrowseCraftCore.KeywordEncoding
typealias PaginationRule = BrowseCraftCore.PaginationRule
typealias RequestConfig = BrowseCraftCore.RequestConfig
typealias RequestScope = BrowseCraftCore.RequestScope
typealias RequestMergePolicy = BrowseCraftCore.RequestMergePolicy
typealias ImageRequestConfig = BrowseCraftCore.ImageRequestConfig
typealias HTTPMethod = BrowseCraftCore.HTTPMethod
typealias RequestBody = BrowseCraftCore.RequestBody
typealias CookiePolicy = BrowseCraftCore.CookiePolicy
typealias CookiePriority = BrowseCraftCore.CookiePriority
typealias CookieScope = BrowseCraftCore.CookieScope
typealias Charset = BrowseCraftCore.Charset
typealias VideoRule = BrowseCraftCore.VideoRule
typealias ContentType = BrowseCraftCore.ContentType

extension BrowseCraftCore.SiteRule {
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
