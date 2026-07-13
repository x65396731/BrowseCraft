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
            self.currentItem?.link = Self.feedURL(value)
        case (.entry, "summary"), (.entry, "content"):
            self.currentItem?.summary = value
            self.currentItem?.applyFallbackCoverURL(Self.firstImageURL(in: value))
            self.currentItem?.appendContentBlocks(Self.contentBlocks(in: value))
        case (.item, "description"):
            self.currentItem?.summary = value
            self.currentItem?.applyFallbackCoverURL(Self.firstImageURL(in: value))
            self.currentItem?.appendContentBlocks(Self.contentBlocks(in: value))
        case (.item, "content:encoded"), (.item, "encoded"):
            self.currentItem?.applyFallbackCoverURL(Self.firstImageURL(in: value))
            self.currentItem?.appendContentBlocks(Self.contentBlocks(in: value))
        case (.item, "thumb"), (.item, "thumbnail"), (.item, "cover"), (.item, "image"):
            self.currentItem?.applyFallbackCoverURL(Self.feedURL(value))
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
        case (.item, "itunes:duration"), (.item, "duration"), (.entry, "itunes:duration"):
            self.currentItem?.applyDuration(value)
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
            if rel == "enclosure" {
                let url: URL? = Self.attributeURL(attributes["href"])
                if RSSMediaClassifier.imageKind(mimeType: attributes["type"], url: url) {
                    self.currentItem?.applyFallbackCoverURL(url)
                } else {
                    self.currentItem?.applyMediaCandidate(
                        Self.mediaCandidate(
                            url: url,
                            mimeType: attributes["type"],
                            playbackMode: .directMedia,
                            duration: attributes["duration"]
                        )
                    )
                }
            } else if rel == "alternate" || rel.isEmpty {
                self.currentItem?.applyFallbackLink(Self.attributeURL(attributes["href"]))
            }
        case "media:thumbnail", "thumbnail":
            self.currentItem?.applyFallbackCoverURL(Self.attributeURL(attributes["url"]))
        case "media:content", "content":
            self.applyMediaContentAttributes(attributes)
        case "media:player":
            self.currentItem?.applyMediaCandidate(
                Self.mediaCandidate(
                    url: Self.attributeURL(attributes["url"]),
                    mimeType: attributes["type"],
                    playbackMode: .webPage,
                    explicitMedium: attributes["medium"],
                    duration: attributes["duration"]
                )
            )
        case "itunes:image":
            self.currentItem?.applyFallbackCoverURL(Self.attributeURL(attributes["href"] ?? attributes["url"]))
        case "enclosure":
            let url: URL? = Self.attributeURL(attributes["url"])
            if RSSMediaClassifier.imageKind(mimeType: attributes["type"], url: url) {
                self.currentItem?.applyFallbackCoverURL(url)
            } else {
                self.currentItem?.applyMediaCandidate(
                    Self.mediaCandidate(
                        url: url,
                        mimeType: attributes["type"],
                        playbackMode: .directMedia,
                        duration: attributes["duration"]
                    )
                )
            }
        default:
            break
        }
    }

    private func applyMediaContentAttributes(_ attributes: [String: String]) {
        let url: URL? = Self.attributeURL(attributes["url"])
        let type: String? = attributes["type"]
        let medium: String? = attributes["medium"]

        if RSSMediaClassifier.imageKind(mimeType: type, url: url) || medium?.lowercased() == "image" {
            self.currentItem?.applyFallbackCoverURL(url)
            return
        }

        self.currentItem?.applyMediaCandidate(
            Self.mediaCandidate(
                url: url,
                mimeType: type,
                playbackMode: .directMedia,
                explicitMedium: medium,
                duration: attributes["duration"]
            )
        )
    }

    private static func normalizedName(elementName: String, qualifiedName: String?) -> String {
        return (qualifiedName ?? elementName).lowercased()
    }

    private static func attributeURL(_ string: String?) -> URL? {
        guard let string: String = string?.trimmedNonEmpty else {
            return nil
        }

        return Self.feedURL(string)
    }

    private static func feedURL(_ rawString: String?) -> URL? {
        guard var string: String = rawString?.trimmedNonEmpty else {
            return nil
        }

        string = Self.decodedHTMLEntities(in: string)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u002f", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while let lastCharacter: Character = string.last,
              [")", "]", "}", ","].contains(lastCharacter) {
            string.removeLast()
        }

        guard string.isEmpty == false,
              string.hasPrefix("data:") == false,
              string.hasPrefix("blob:") == false,
              string != "#",
              string.lowercased() != "about:blank",
              Self.isTemplateImageURL(string) == false else {
            return nil
        }

        if string.hasPrefix("//") {
            return URL(string: "https:\(string)")
        }

        return URL(string: string)
    }

    private static func isTemplateImageURL(_ urlString: String) -> Bool {
        let lowercasedURL: String = urlString.lowercased()
        return lowercasedURL.contains("${")
            || lowercasedURL.contains("%7b")
            || lowercasedURL.contains("escapehtml(")
            || lowercasedURL.contains("imgsmallurl")
            || lowercasedURL.contains("imgbannerurl")
            || lowercasedURL.contains("imgbigurl")
    }

    private static func mediaCandidate(
        url: URL?,
        mimeType: String?,
        playbackMode: RSSContentPayload.MediaPlaybackMode,
        explicitMedium: String? = nil,
        duration: String? = nil
    ) -> RSSContentPayload.Media? {
        guard let url: URL = url else {
            return nil
        }

        let kind: RSSContentPayload.MediaKind?
        switch explicitMedium?.lowercased() {
        case "audio":
            kind = .audio
        case "video":
            kind = .video
        default:
            if playbackMode == .webPage {
                kind = .video
            } else {
                kind = RSSMediaClassifier.directMediaKind(mimeType: mimeType, url: url)
            }
        }

        guard let kind: RSSContentPayload.MediaKind = kind else {
            return nil
        }

        return RSSContentPayload.Media(
            kind: kind,
            playbackMode: playbackMode,
            url: url.absoluteString,
            mimeType: mimeType?.trimmedNonEmpty ?? RSSMediaClassifier.mimeType(for: url),
            duration: duration?.trimmedNonEmpty,
            posterURL: nil,
            sourcePageURL: nil
        )
    }

    private static func firstImageURL(in html: String?) -> URL? {
        guard let html: String = html else {
            return nil
        }

        return Self.imageURLs(in: Self.articleHTML(in: html) ?? html).first
    }

    private static func contentBlocks(in html: String?) -> [RSSContentPayload.Block] {
        guard let html: String = html else {
            return []
        }

        let contentHTML: String = Self.articleHTML(in: html) ?? html
        let pattern: String = #"(?is)<h[1-6]\b[^>]*>(.*?)</h[1-6]>|<p\b[^>]*>(.*?)</p>|<img\b[^>]*>"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range: NSRange = NSRange(contentHTML.startIndex..<contentHTML.endIndex, in: contentHTML)
        let matches: [NSTextCheckingResult] = regex.matches(in: contentHTML, range: range)
        var blocks: [RSSContentPayload.Block] = []
        var seenImageURLs: Set<String> = []

        for match in matches {
            guard let fullRange: Range<String.Index> = Range(match.range(at: 0), in: contentHTML) else {
                continue
            }

            let fullMatch: String = String(contentHTML[fullRange])
            let lowercasedMatch: String = fullMatch.lowercased()

            if lowercasedMatch.hasPrefix("<img") {
                Self.appendImages(from: fullMatch, to: &blocks, seenImageURLs: &seenImageURLs)
                continue
            }

            if match.numberOfRanges > 1,
               let headingRange: Range<String.Index> = Range(match.range(at: 1), in: contentHTML),
               let text: String = Self.plainText(from: String(contentHTML[headingRange])) {
                blocks.append(Self.block(kind: .subtitle, text: text, imageURL: nil, index: blocks.count))
                continue
            }

            if match.numberOfRanges > 2,
               let paragraphRange: Range<String.Index> = Range(match.range(at: 2), in: contentHTML) {
                let paragraphHTML: String = String(contentHTML[paragraphRange])

                if let text: String = Self.plainText(from: paragraphHTML) {
                    blocks.append(
                        Self.block(
                            kind: Self.paragraphBlockKind(html: paragraphHTML, text: text),
                            text: text,
                            imageURL: nil,
                            index: blocks.count
                        )
                    )
                }

                Self.appendImages(from: paragraphHTML, to: &blocks, seenImageURLs: &seenImageURLs)
            }
        }

        if blocks.isEmpty,
           let text: String = Self.plainText(from: contentHTML) {
            blocks.append(Self.block(kind: .paragraph, text: text, imageURL: nil, index: 0))
        }

        return blocks
    }

    private static func articleHTML(in html: String) -> String? {
        let markers: [String] = [
            #"<div class="topic_content""#,
            #"<div class='topic_content'"#,
            #"<div class="nfzm-content__fulltext"#,
            #"<div class='nfzm-content__fulltext"#,
            #"<div class="article--content"#,
            #"<div class='article--content"#
        ]

        guard let startMatch: (marker: String, range: Range<String.Index>) = markers.compactMap({ marker in
            html.range(of: marker).map { range in
                (marker: marker, range: range)
            }
        }).min(by: { lhs, rhs in lhs.range.lowerBound < rhs.range.lowerBound }) else {
            return nil
        }

        if startMatch.marker.hasPrefix("<div"),
           let elementHTML: String = Self.balancedDivHTML(in: html, startingAt: startMatch.range.lowerBound) {
            return elementHTML
        }

        let tail: Substring = html[startMatch.range.lowerBound...]
        let endMarkers: [String] = [
            #"<!--fulltext end-->"#
        ]

        if let endRange: Range<Substring.Index> = endMarkers.compactMap({ marker in
            tail.range(of: marker)
        }).min(by: { lhs, rhs in lhs.lowerBound < rhs.lowerBound }) {
            return String(tail[..<endRange.lowerBound])
        }

        return String(tail)
    }

    private static func balancedDivHTML(in html: String, startingAt startIndex: String.Index) -> String? {
        guard html[startIndex...].lowercased().hasPrefix("<div") else {
            return nil
        }

        let tagRegex: NSRegularExpression
        do {
            tagRegex = try NSRegularExpression(pattern: #"(?is)<\s*/?\s*div\b[^>]*>"#)
        } catch {
            return nil
        }

        let range: NSRange = NSRange(startIndex..<html.endIndex, in: html)
        var depth: Int = 0
        for match in tagRegex.matches(in: html, range: range) {
            guard let tagRange: Range<String.Index> = Range(match.range(at: 0), in: html) else {
                continue
            }

            let tag: String = String(html[tagRange]).lowercased()
            if tag.hasPrefix("</") {
                depth -= 1
            } else {
                depth += 1
            }

            if depth == 0 {
                return String(html[startIndex..<tagRange.upperBound])
            }
        }

        return nil
    }

    private static func paragraphBlockKind(html: String, text: String) -> RSSContentPayload.BlockKind {
        if Self.isEmphasizedParagraph(html: html, text: text) {
            return .subtitle
        }

        if Self.isColonHeadingLikeText(text) {
            return .subtitle
        }

        return .paragraph
    }

    private static func isEmphasizedParagraph(html: String, text: String) -> Bool {
        let pattern: String = #"(?is)<(?:strong|b|em)\b[^>]*>(.*?)</(?:strong|b|em)>"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        let range: NSRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let emphasizedText: String = regex.matches(in: html, range: range)
            .compactMap { match in
                guard match.numberOfRanges > 1,
                      let textRange: Range<String.Index> = Range(match.range(at: 1), in: html) else {
                    return nil
                }

                return Self.plainText(from: String(html[textRange]))
            }
            .joined(separator: " ")

        guard let normalizedEmphasizedText: String = emphasizedText.trimmedNonEmpty else {
            return false
        }

        return normalizedEmphasizedText == text
    }

    private static func isColonHeadingLikeText(_ text: String) -> Bool {
        if text.count > 34 {
            return false
        }

        return text.contains("：") || text.contains(":")
    }

    private static func appendImages(
        from html: String,
        to blocks: inout [RSSContentPayload.Block],
        seenImageURLs: inout Set<String>
    ) {
        for url in Self.imageURLs(in: html) {
            let urlString: String = url.absoluteString
            guard seenImageURLs.contains(urlString) == false else {
                continue
            }

            seenImageURLs.insert(urlString)
            blocks.append(Self.block(kind: .image, text: nil, imageURL: urlString, index: blocks.count))
        }
    }

    private static func imageURLs(in html: String?) -> [URL] {
        guard let html: String = html else {
            return []
        }

        let imageTagPattern: String = #"<img\b[^>]*>"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(
            pattern: imageTagPattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let imageURLAttributes: [String] = [
            "data-original",
            "data-original-src",
            "data-src",
            "data-lazy-src",
            "data-actualsrc",
            "data-url",
            "data-file",
            "data-image",
            "data-echo",
            "data-lazy",
            "data-full",
            "src"
        ]

        var urls: [URL] = []
        var seenURLStrings: Set<String> = []
        let range: NSRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let tagRange: Range<String.Index> = Range(match.range(at: 0), in: html) else {
                continue
            }

            let tag: String = String(html[tagRange])
            if Self.isDecorativeProfileImageTag(tag, in: html, at: tagRange.lowerBound) {
                continue
            }

            for attributeName in imageURLAttributes {
                guard let rawURLString: String = Self.attributeValue(named: attributeName, in: tag),
                      let url: URL = Self.feedURL(rawURLString) else {
                    continue
                }

                let urlString: String = url.absoluteString
                guard seenURLStrings.contains(urlString) == false else {
                    continue
                }

                seenURLStrings.insert(urlString)
                urls.append(url)
            }
        }

        return urls
    }

    private static func isDecorativeProfileImageTag(
        _ tag: String,
        in html: String,
        at tagStartIndex: String.Index
    ) -> Bool {
        let tagContext: String = Self.decorativeImageContext(around: tag, in: html, at: tagStartIndex)
        let semanticFragments: [String] = [
            "avatar",
            "author",
            "authorcard",
            "author-card",
            "user-icon",
            "user_icon",
            "usertag",
            "user-tag",
            "profile",
            "portrait",
            "headimg",
            "head-img"
        ]

        return semanticFragments.contains { fragment in
            tagContext.contains(fragment)
        }
    }

    private static func decorativeImageContext(
        around tag: String,
        in html: String,
        at tagStartIndex: String.Index
    ) -> String {
        let prefixStart: String.Index = html.index(
            tagStartIndex,
            offsetBy: -min(240, html.distance(from: html.startIndex, to: tagStartIndex))
        )
        let prefix: String = String(html[prefixStart..<tagStartIndex])
        let tagAttributes: String = [
            Self.attributeValue(named: "class", in: tag),
            Self.attributeValue(named: "alt", in: tag),
            Self.attributeValue(named: "title", in: tag),
            Self.attributeValue(named: "aria-label", in: tag)
        ]
            .compactMap { $0 }
            .joined(separator: " ")

        return "\(prefix) \(tagAttributes)".lowercased()
    }

    private static func attributeValue(named attributeName: String, in tag: String) -> String? {
        let pattern: String = #"\b\#(NSRegularExpression.escapedPattern(for: attributeName))\s*=\s*(["'])(.*?)\1"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let range: NSRange = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match: NSTextCheckingResult = regex.firstMatch(in: tag, range: range),
              match.numberOfRanges > 2,
              let valueRange: Range<String.Index> = Range(match.range(at: 2), in: tag) else {
            return nil
        }

        return String(tag[valueRange]).trimmedNonEmpty
    }

    private static func decodedHTMLEntities(in text: String) -> String {
        return text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func block(
        kind: RSSContentPayload.BlockKind,
        text: String?,
        imageURL: String?,
        index: Int
    ) -> RSSContentPayload.Block {
        return RSSContentPayload.Block(
            id: "\(kind.rawValue)-\(index)",
            kind: kind,
            text: text,
            imageURL: imageURL
        )
    }

    private static func plainText(from html: String) -> String? {
        let withoutTags: String = html.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let decoded: String = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        let collapsed: String = decoded
            .split(whereSeparator: { character in
                return character.isWhitespace
            })
            .joined(separator: " ")

        return collapsed.trimmedNonEmpty
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
    var media: RSSContentPayload.Media?
    var pendingDuration: String?
    var contentBlocks: [RSSContentPayload.Block] = []
    var publishedAt: Date?
    var guid: String?

    var feedItem: RSSFeedItem {
        return RSSFeedItem(
            title: self.title,
            link: self.link,
            summary: self.summary,
            coverURL: self.coverURL,
            media: self.mediaWithPoster,
            contentBlocks: self.contentBlocks,
            publishedAt: self.publishedAt,
            guid: self.guid
        )
    }

    private var mediaWithPoster: RSSContentPayload.Media? {
        guard var media: RSSContentPayload.Media = self.media else {
            return nil
        }

        if media.posterURL == nil {
            media.posterURL = self.coverURL?.absoluteString
        }

        return media
    }

    mutating func applyFallbackCoverURL(_ url: URL?) {
        if self.coverURL == nil {
            self.coverURL = url
        }
        if self.media?.posterURL == nil {
            self.media?.posterURL = url?.absoluteString
        }
    }

    mutating func applyFallbackLink(_ url: URL?) {
        if self.link == nil {
            self.link = url
        }
    }

    mutating func applyMediaCandidate(_ candidate: RSSContentPayload.Media?) {
        guard var candidate: RSSContentPayload.Media = candidate else {
            return
        }

        if candidate.posterURL == nil {
            candidate.posterURL = self.coverURL?.absoluteString
        }
        if candidate.duration == nil {
            candidate.duration = self.pendingDuration
        }

        guard let media: RSSContentPayload.Media = self.media else {
            self.media = candidate
            return
        }

        if media.playbackMode == .webPage, candidate.playbackMode == .directMedia {
            candidate.duration = candidate.duration ?? media.duration
            candidate.posterURL = candidate.posterURL ?? media.posterURL
            self.media = candidate
        }
    }

    mutating func applyDuration(_ duration: String?) {
        guard let duration: String = duration?.trimmedNonEmpty else {
            return
        }

        self.pendingDuration = duration
        if self.media?.duration == nil {
            self.media?.duration = duration
        }
    }

    mutating func appendContentBlocks(_ blocks: [RSSContentPayload.Block]) {
        guard blocks.isEmpty == false else {
            return
        }

        if self.contentBlocks.isEmpty {
            self.contentBlocks = blocks
        } else {
            self.contentBlocks.append(contentsOf: blocks)
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
