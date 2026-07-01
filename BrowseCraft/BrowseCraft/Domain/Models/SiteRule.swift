import Foundation

// 中文注释：SiteRule.swift 属于领域模型层，用于说明本文件承载的核心职责。

/// 中文注释：站点规则描述 BrowseCraft 如何从某个源站抽取内容。
/// 中文注释：它属于领域数据，不关心底层使用 SwiftSoup、JSON 解析器还是其他解析器。
struct SiteRule: Codable, Hashable {
    var name: String
    var baseUrl: String
    var list: ListRule
    var detail: DetailRule?
    var gallery: GalleryRule?
    var video: VideoRule?
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

    /// 中文注释：MyComic 内置规则，来源于 https://mycomic.com/cn。
    /// 中文注释：阅读页里可能先出现随机漫画链接，因此必须用面包屑或目录链接判断真实作品关系。
    static let myComicJSON: String = """
    {
      "name": "MYCOMIC",
      "baseUrl": "https://mycomic.com/cn",
      "list": {
        "url": "https://mycomic.com/cn/comics?sort=-update&page={page}",
        "item": "a[href*=\\\"/cn/comics/\\\"]:has(img)",
        "title": "img@alt",
        "link": "this@href",
        "cover": "img@data-src|src",
        "type": "comic",
        "latestText": "parent a[href*=\\\"/cn/chapters/\\\"]"
      },
      "detail": {
        "title": "h1",
        "cover": "img[src*=\\\"/comics/\\\"], img[data-src*=\\\"/comics/\\\"]@data-src|src",
        "chapterContainer": "section:contains(章节), section:contains(章節), div:has(> h2:contains(章节)), div:has(> h2:contains(章節)), div:has(> h3:contains(章节)), div:has(> h3:contains(章節))",
        "chapterItem": "a[href*=\\\"/cn/chapters/\\\"]",
        "chapterTitle": "this",
        "chapterLink": "this@href"
      },
      "gallery": {
        "imageItem": "img.page, img[src*=\\\"/chapters/\\\"], img[data-src*=\\\"/chapters/\\\"]",
        "imageUrl": "this@data-src|src",
        "comicTitle": "[data-flux-breadcrumbs-item] a[href*=\\\"/cn/comics/\\\"]",
        "chapterTitle": "[data-flux-breadcrumbs-item] .truncate",
        "catalogLink": "a:contains(返回目录)@href",
        "previousLink": "a:contains(上一话)@href",
        "nextLink": "a:contains(下一话)@href"
      }
    }
    """
}
