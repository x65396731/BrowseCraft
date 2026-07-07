import Foundation

// 中文注释：RSSFeedMapper 只负责把 RSS XML 转成 RSS runtime 内部模型。
struct RSSFeedMapper {
    func map(_ xml: String) throws -> RSSFeed {
        guard let data: Data = xml.data(using: .utf8) else {
            throw RSSFeedMapperError.invalidEncoding
        }

        return try self.map(data)
    }

    func map(_ data: Data) throws -> RSSFeed {
        let delegate: RSSFeedMapperDelegate = RSSFeedMapperDelegate()
        let parser: XMLParser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw parser.parserError ?? RSSFeedMapperError.invalidXML
        }

        return RSSFeed(
            title: delegate.feedTitle?.trimmedNonEmpty,
            items: delegate.items
        )
    }
}

enum RSSFeedMapperError: Error, Equatable {
    case invalidEncoding
    case invalidXML
}

private final class RSSFeedMapperDelegate: NSObject, XMLParserDelegate {
    private enum Context {
        case channel
        case feed
        case item
        case entry
        case other
    }

    private var contextStack: [Context] = []
    private var currentElementName: String?
    private var currentText: String = ""
    private var currentItem: MutableRSSFeedItem?

    private(set) var feedTitle: String?
    private(set) var items: [RSSFeedItem] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let normalizedName: String = Self.normalizedName(elementName: elementName, qualifiedName: qName)
        self.currentElementName = normalizedName
        self.currentText = ""

        if self.contextStack.last == .item || self.contextStack.last == .entry {
            self.applyElementAttributesIfNeeded(elementName: normalizedName, attributes: attributeDict)
        }

        if normalizedName == "feed" {
            self.contextStack.append(.feed)
            return
        }

        if normalizedName == "channel" {
            self.contextStack.append(.channel)
            return
        }

        if normalizedName == "entry" {
            self.contextStack.append(.entry)
            self.currentItem = MutableRSSFeedItem()
            return
        }

        if normalizedName == "item" {
            self.contextStack.append(.item)
            self.currentItem = MutableRSSFeedItem()
            return
        }

        self.contextStack.append(self.contextStack.last ?? .other)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        self.currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string: String = String(data: CDATABlock, encoding: .utf8) {
            self.currentText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let normalizedName: String = Self.normalizedName(elementName: elementName, qualifiedName: qName)
        let value: String? = self.currentText.trimmedNonEmpty
        let context: Context = self.contextStack.last ?? .other

        switch (context, normalizedName) {
        case (.feed, "title"):
            if self.feedTitle == nil {
                self.feedTitle = value
            }
        case (.channel, "title"):
            if self.feedTitle == nil {
                self.feedTitle = value
            }
        case (.item, "title"):
            self.currentItem?.title = value
        case (.entry, "title"):
            self.currentItem?.title = value
        case (.item, "link"):
            self.currentItem?.link = value.flatMap(URL.init(string:))
        case (.entry, "summary"), (.entry, "content"):
            self.currentItem?.summary = value
            self.currentItem?.applyFallbackCoverURL(Self.firstImageURL(in: value))
        case (.item, "description"):
            self.currentItem?.summary = value
            self.currentItem?.applyFallbackCoverURL(Self.firstImageURL(in: value))
        case (.item, "content:encoded"), (.item, "encoded"):
            self.currentItem?.applyFallbackCoverURL(Self.firstImageURL(in: value))
        case (.item, "thumb"), (.item, "thumbnail"), (.item, "cover"), (.item, "image"):
            self.currentItem?.applyFallbackCoverURL(value.flatMap(URL.init(string:)))
        case (.item, "pubdate"):
            self.currentItem?.publishedAt = value.flatMap(Self.date(from:))
        case (.entry, "published"), (.entry, "updated"):
            if self.currentItem?.publishedAt == nil {
                self.currentItem?.publishedAt = value.flatMap(Self.date(from:))
            }
        case (.item, "guid"):
            self.currentItem?.guid = value
        case (.entry, "id"):
            self.currentItem?.guid = value
        default:
            break
        }

        if (normalizedName == "item" || normalizedName == "entry"),
           let currentItem: MutableRSSFeedItem = self.currentItem {
            self.items.append(currentItem.feedItem)
            self.currentItem = nil
        }

        _ = self.contextStack.popLast()
        self.currentElementName = nil
        self.currentText = ""
    }

    private func applyElementAttributesIfNeeded(elementName: String, attributes: [String: String]) {
        guard self.currentItem != nil else {
            return
        }

        switch elementName {
        case "link":
            let rel: String = attributes["rel"]?.lowercased() ?? "alternate"
            if rel == "alternate" || rel.isEmpty {
                self.currentItem?.applyFallbackLink(Self.attributeURL(attributes["href"]))
            }
        case "media:thumbnail", "media:content", "thumbnail", "content":
            self.currentItem?.applyFallbackCoverURL(Self.attributeURL(attributes["url"]))
        case "itunes:image":
            self.currentItem?.applyFallbackCoverURL(Self.attributeURL(attributes["href"] ?? attributes["url"]))
        case "enclosure":
            let type: String = attributes["type"]?.lowercased() ?? ""
            let urlString: String? = attributes["url"]
            if type.hasPrefix("image/") || Self.looksLikeImageURL(urlString) {
                self.currentItem?.applyFallbackCoverURL(Self.attributeURL(urlString))
            }
        default:
            break
        }
    }

    private static func normalizedName(elementName: String, qualifiedName: String?) -> String {
        return (qualifiedName ?? elementName).lowercased()
    }

    private static func attributeURL(_ string: String?) -> URL? {
        guard let string: String = string?.trimmedNonEmpty else {
            return nil
        }

        return URL(string: string)
    }

    private static func firstImageURL(in html: String?) -> URL? {
        guard let html: String = html else {
            return nil
        }

        let pattern: String = #"<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let range: NSRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match: NSTextCheckingResult = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let urlRange: Range<String.Index> = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return URL(string: String(html[urlRange]))
    }

    private static func looksLikeImageURL(_ string: String?) -> Bool {
        guard let string: String = string?.lowercased() else {
            return false
        }

        return string.contains(".jpg")
            || string.contains(".jpeg")
            || string.contains(".png")
            || string.contains(".webp")
            || string.contains(".gif")
            || string.contains(".avif")
    }

    private static func date(from string: String) -> Date? {
        if let date: Date = Self.iso8601DateFormatter.date(from: string)
            ?? Self.iso8601FractionalDateFormatter.date(from: string) {
            return date
        }

        for formatter in Self.dateFormatters {
            if let date: Date = formatter.date(from: string) {
                return date
            }
        }

        return nil
    }

    private static let dateFormatters: [DateFormatter] = {
        let locales: [Locale] = [Locale(identifier: "en_US_POSIX")]
        let formats: [String] = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z"
        ]

        return formats.map { format in
            let formatter: DateFormatter = DateFormatter()
            formatter.locale = locales[0]
            formatter.dateFormat = format
            return formatter
        }
    }()

    private static let iso8601DateFormatter: ISO8601DateFormatter = {
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601FractionalDateFormatter: ISO8601DateFormatter = {
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct MutableRSSFeedItem {
    var title: String?
    var link: URL?
    var summary: String?
    var coverURL: URL?
    var publishedAt: Date?
    var guid: String?

    var feedItem: RSSFeedItem {
        return RSSFeedItem(
            title: self.title,
            link: self.link,
            summary: self.summary,
            coverURL: self.coverURL,
            publishedAt: self.publishedAt,
            guid: self.guid
        )
    }

    mutating func applyFallbackCoverURL(_ url: URL?) {
        if self.coverURL == nil {
            self.coverURL = url
        }
    }

    mutating func applyFallbackLink(_ url: URL?) {
        if self.link == nil {
            self.link = url
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
