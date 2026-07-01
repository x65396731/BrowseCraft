import Foundation

/// A site rule describes how BrowseCraft should extract content from a source.
///
/// This type belongs to Domain because it is business data. It does not know
/// whether the parser is SwiftSoup, a JSON parser, or something else.
struct SiteRule: Codable, Hashable {
    var name: String
    var baseUrl: String
    var list: ListRule
    var detail: DetailRule?
    var gallery: GalleryRule?
    var video: VideoRule?
}

struct ListRule: Codable, Hashable {
    var url: String
    var item: String
    var title: String
    var link: String
    var cover: String?
    var type: ContentType
    var latestText: String?
}

struct DetailRule: Codable, Hashable {
    var title: String?
    var cover: String?
    var chapterItem: String?
    var chapterTitle: String?
    var chapterLink: String?
}

struct GalleryRule: Codable, Hashable {
    var imageItem: String
    var imageUrl: String
}

struct VideoRule: Codable, Hashable {
    var videoUrl: String
}

extension SiteRule {
    /// A visible example used by AddSourceView so new users can learn the JSON format.
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
}

