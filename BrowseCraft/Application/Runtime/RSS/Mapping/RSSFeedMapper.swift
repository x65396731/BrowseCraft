import Foundation

// 中文注释：RSSFeedMapper 只负责把 RSS XML 转成 RSS runtime 内部模型。
struct RSSFeedMapper {
    func map(_ xml: String) throws -> RSSFeed {
        guard let data: Data = xml.data(using: .utf8) else {
            throw RSSFeedMapperError.invalidEncoding
        }

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
        case item
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
        let normalizedName: String = elementName.lowercased()
        self.currentElementName = normalizedName
        self.currentText = ""

        if normalizedName == "channel" {
            self.contextStack.append(.channel)
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

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let normalizedName: String = elementName.lowercased()
        let value: String? = self.currentText.trimmedNonEmpty
        let context: Context = self.contextStack.last ?? .other

        switch (context, normalizedName) {
        case (.channel, "title"):
            if self.feedTitle == nil {
                self.feedTitle = value
            }
        case (.item, "title"):
            self.currentItem?.title = value
        case (.item, "link"):
            self.currentItem?.link = value.flatMap(URL.init(string:))
        case (.item, "description"):
            self.currentItem?.summary = value
        case (.item, "pubdate"):
            self.currentItem?.publishedAt = value.flatMap(Self.date(from:))
        case (.item, "guid"):
            self.currentItem?.guid = value
        default:
            break
        }

        if normalizedName == "item", let currentItem: MutableRSSFeedItem = self.currentItem {
            self.items.append(currentItem.feedItem)
            self.currentItem = nil
        }

        _ = self.contextStack.popLast()
        self.currentElementName = nil
        self.currentText = ""
    }

    private static func date(from string: String) -> Date? {
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
}

private struct MutableRSSFeedItem {
    var title: String?
    var link: URL?
    var summary: String?
    var publishedAt: Date?
    var guid: String?

    var feedItem: RSSFeedItem {
        return RSSFeedItem(
            title: self.title,
            link: self.link,
            summary: self.summary,
            publishedAt: self.publishedAt,
            guid: self.guid
        )
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
