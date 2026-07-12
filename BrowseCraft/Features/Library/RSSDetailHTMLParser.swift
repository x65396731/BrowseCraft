import Foundation

// 中文注释：RSSDetailHTMLParser 只解析 RSS detailURL 的网页正文，不参与 RSS feed XML 规则映射。
struct RSSDetailHTMLParser {
    struct DetailContent {
        var blocks: [RSSContentPayload.Block]
        var metadata: RSSContentPayload.Metadata
    }

    static func detailContentBlocks(in html: String, pageURL: URL) -> [RSSContentPayload.Block] {
        return Self.detailContent(in: html, pageURL: pageURL).blocks
    }

    static func detailContent(in html: String, pageURL: URL) -> DetailContent {
        let articleHTML: String = Self.articleHTML(in: html) ?? html
        return DetailContent(
            blocks: Self.contentBlocks(in: articleHTML, baseURL: pageURL),
            metadata: Self.metadata(in: html, articleHTML: articleHTML)
        )
    }

    private static func articleHTML(in html: String) -> String? {
        let markers: [String] = [
            #"<div class="articlePage_content""#,
            #"<div class='articlePage_content'"#,
            #"class="articlePage_content""#,
            #"class='articlePage_content'"#
        ]

        guard let startRange: Range<String.Index> = markers.compactMap({ marker in
            html.range(of: marker)
        }).min(by: { lhs, rhs in lhs.lowerBound < rhs.lowerBound }) else {
            return nil
        }

        let tail: Substring = html[startRange.lowerBound...]
        let endMarkers: [String] = [
            #"<div class="newsPage_r""#,
            #"<div class='newsPage_r'"#,
            #"<div class="originalPage_bottom""#,
            #"<div class='originalPage_bottom'"#
        ]

        if let endRange: Range<Substring.Index> = endMarkers.compactMap({ marker in
            tail.range(of: marker)
        }).min(by: { lhs, rhs in lhs.lowerBound < rhs.lowerBound }) {
            return String(tail[..<endRange.lowerBound])
        }

        return String(tail)
    }

    private static func contentBlocks(in html: String?, baseURL: URL?) -> [RSSContentPayload.Block] {
        guard let html: String = html else {
            return []
        }

        let draftTextBlocks: [RSSContentPayload.Block] = Self.draftEditorTextBlocks(in: html)
        if draftTextBlocks.isEmpty == false {
            var draftBlocks: [RSSContentPayload.Block] = draftTextBlocks
            var seenImageURLs: Set<String> = []
            Self.appendImages(from: html, baseURL: baseURL, to: &draftBlocks, seenImageURLs: &seenImageURLs)
            return Self.reindexed(draftBlocks)
        }

        let pattern: String = #"(?is)<h[1-6]\b[^>]*>(.*?)</h[1-6]>|<p\b[^>]*>(.*?)</p>|<img\b[^>]*>"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range: NSRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches: [NSTextCheckingResult] = regex.matches(in: html, range: range)
        var blocks: [RSSContentPayload.Block] = []
        var seenImageURLs: Set<String> = []

        for match in matches {
            guard let fullRange: Range<String.Index> = Range(match.range(at: 0), in: html) else {
                continue
            }

            let fullMatch: String = String(html[fullRange])
            let lowercasedMatch: String = fullMatch.lowercased()

            if lowercasedMatch.hasPrefix("<img") {
                Self.appendImages(from: fullMatch, baseURL: baseURL, to: &blocks, seenImageURLs: &seenImageURLs)
                continue
            }

            if match.numberOfRanges > 1,
               let headingRange: Range<String.Index> = Range(match.range(at: 1), in: html),
               let text: String = Self.plainText(from: String(html[headingRange])) {
                blocks.append(Self.block(kind: .subtitle, text: text, imageURL: nil, index: blocks.count))
                continue
            }

            if match.numberOfRanges > 2,
               let paragraphRange: Range<String.Index> = Range(match.range(at: 2), in: html) {
                let paragraphHTML: String = String(html[paragraphRange])

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

                Self.appendImages(from: paragraphHTML, baseURL: baseURL, to: &blocks, seenImageURLs: &seenImageURLs)
            }
        }

        let lineBlocks: [RSSContentPayload.Block] = Self.textOnlyBlocks(in: html)
        let hasTextBlock: Bool = blocks.contains { block in
            block.text?.trimmedNonEmpty != nil
        }

        if hasTextBlock == false, lineBlocks.isEmpty == false {
            let imageBlocks: [RSSContentPayload.Block] = blocks.filter { block in
                block.kind == .image
            }
            return Self.reindexed(lineBlocks + imageBlocks)
        }

        if blocks.isEmpty {
            if lineBlocks.isEmpty == false {
                return lineBlocks
            }

            if let text: String = Self.plainText(from: html) {
                blocks.append(Self.block(kind: .paragraph, text: text, imageURL: nil, index: 0))
            }
        }

        return blocks
    }

    private static func metadata(in html: String, articleHTML: String) -> RSSContentPayload.Metadata {
        return RSSContentPayload.Metadata(
            tags: Self.tags(in: articleHTML),
            likeCount: Self.likeCount(in: articleHTML),
            commentCount: Self.commentCount(in: html)
        )
    }

    private static func tags(in html: String) -> [String] {
        guard let tagsHTML: String = Self.firstMatch(
            pattern: #"(?is)<div\b[^>]*class=["'][^"']*\boriginalPage_btmTags\b[^"']*["'][^>]*>(.*?)</div>\s*</div>"#,
            in: html
        ) ?? Self.firstMatch(
            pattern: #"(?is)<div\b[^>]*class=["'][^"']*\boriginalPage_labels\b[^"']*["'][^>]*>(.*?)</div>"#,
            in: html
        ) else {
            return []
        }

        let tagHTMLs: [String] = Self.matches(
            pattern: #"(?is)<a\b[^>]*class=["'][^"']*\bis_tags\b[^"']*["'][^>]*>(.*?)</a>"#,
            in: tagsHTML
        )
        var tags: [String] = []
        var seenTags: Set<String> = []

        for tagHTML in tagHTMLs {
            guard let tag: String = Self.plainText(from: tagHTML),
                  seenTags.contains(tag) == false else {
                continue
            }

            seenTags.insert(tag)
            tags.append(tag)
        }

        return tags
    }

    private static func likeCount(in html: String) -> Int? {
        let patterns: [String] = [
            #"(?is)<a\b[^>]*class=["'][^"']*\bo_vote-up\b[^"']*["'][^>]*>.*?<span\b[^>]*class=["'][^"']*\bo_action_num\b[^"']*["'][^>]*>\s*([0-9,]+)\s*</span>"#,
            #"(?is)<span\b[^>]*class=["'][^"']*\bo_action_num\b[^"']*["'][^>]*>\s*([0-9,]+)\s*</span>"#
        ]

        return patterns.lazy.compactMap { pattern in
            Self.firstInteger(pattern: pattern, in: html)
        }.first
    }

    private static func commentCount(in html: String) -> Int? {
        let patterns: [String] = [
            #"(?is)<p\b[^>]*class=["'][^"']*\bcommentsMana_sortTabs\b[^"']*["'][^>]*>.*?共\s*<!-- -->?\s*([0-9,]+)\s*<!-- -->?\s*条\s*<!-- -->?\s*评论"#,
            #"(?is)共\s*<!-- -->?\s*([0-9,]+)\s*<!-- -->?\s*条\s*<!-- -->?\s*评论"#
        ]

        return patterns.lazy.compactMap { pattern in
            Self.firstInteger(pattern: pattern, in: html)
        }.first
    }

    private static func reindexed(_ blocks: [RSSContentPayload.Block]) -> [RSSContentPayload.Block] {
        return blocks.enumerated().map { index, block in
            Self.block(kind: block.kind, text: block.text, imageURL: block.imageURL, index: index)
        }
    }

    private static func paragraphBlockKind(html: String, text: String) -> RSSContentPayload.BlockKind {
        if Self.isEmphasizedParagraph(html: html, text: text) {
            return .subtitle
        }

        if Self.isShortHeadingLikeText(text) {
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

    private static func isShortHeadingLikeText(_ text: String) -> Bool {
        let characterCount: Int = text.count
        if characterCount > 34 {
            return false
        }

        if text.contains("：") || text.contains(":") {
            return true
        }

        return characterCount <= 18 && text.contains("。") == false && text.contains("，") == false
    }

    private static func appendImages(
        from html: String,
        baseURL: URL?,
        to blocks: inout [RSSContentPayload.Block],
        seenImageURLs: inout Set<String>
    ) {
        for url in Self.imageURLs(in: html, baseURL: baseURL) {
            let urlString: String = url.absoluteString
            guard seenImageURLs.contains(urlString) == false else {
                continue
            }

            seenImageURLs.insert(urlString)
            blocks.append(Self.block(kind: .image, text: nil, imageURL: urlString, index: blocks.count))
        }
    }

    private static func imageURLs(in html: String?, baseURL: URL?) -> [URL] {
        guard let html: String = html else {
            return []
        }

        var urls: [URL] = []
        var seenURLStrings: Set<String> = []

        let imageTagPattern: String = #"<img\b[^>]*>"#
        if let imageTagRegex: NSRegularExpression = try? NSRegularExpression(
            pattern: imageTagPattern,
            options: [.caseInsensitive]
        ) {
            let range: NSRange = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in imageTagRegex.matches(in: html, range: range) {
                guard let tagRange: Range<String.Index> = Range(match.range(at: 0), in: html) else {
                    continue
                }

                let tag: String = String(html[tagRange])
                for attributeName in ["data-original", "data-src", "src"] {
                    if let rawURLString: String = Self.attributeValue(named: attributeName, in: tag) {
                        Self.appendImageURL(
                            rawURLString,
                            baseURL: baseURL,
                            to: &urls,
                            seenURLStrings: &seenURLStrings
                        )
                        break
                    }
                }

                for attributeName in ["data-srcset", "srcset"] {
                    guard let srcset: String = Self.attributeValue(named: attributeName, in: tag),
                          let rawURLString: String = Self.preferredSrcsetURL(in: srcset) else {
                        continue
                    }

                    Self.appendImageURL(
                        rawURLString,
                        baseURL: baseURL,
                        to: &urls,
                        seenURLStrings: &seenURLStrings
                    )
                }
            }
        }

        let embeddedURLPatterns: [String] = [
            #"https?:\\?/\\?/image\.gcores\.com/[^"'<>\s]+"#,
            #"//image\.gcores\.com/[^"'<>\s]+"#
        ]

        for pattern in embeddedURLPatterns {
            guard let regex: NSRegularExpression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else {
                continue
            }

            let range: NSRange = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, range: range) {
                guard let urlRange: Range<String.Index> = Range(match.range(at: 0), in: html) else {
                    continue
                }

                Self.appendImageURL(
                    String(html[urlRange]),
                    baseURL: baseURL,
                    to: &urls,
                    seenURLStrings: &seenURLStrings
                )
            }
        }

        return urls
    }

    private static func attributeValue(named name: String, in html: String) -> String? {
        let pattern: String = #"\b\#(name)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let range: NSRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match: NSTextCheckingResult = regex.firstMatch(in: html, range: range) else {
            return nil
        }

        for index in 1..<match.numberOfRanges {
            let nsRange: NSRange = match.range(at: index)
            guard nsRange.location != NSNotFound,
                  let valueRange: Range<String.Index> = Range(nsRange, in: html) else {
                continue
            }

            if let value: String = String(html[valueRange]).trimmedNonEmpty {
                return value
            }
        }

        return nil
    }

    private static func preferredSrcsetURL(in srcset: String) -> String? {
        return srcset
            .split(separator: ",")
            .compactMap { candidate -> String? in
                guard let firstPart: Substring = candidate
                    .split(whereSeparator: { character in character.isWhitespace })
                    .first else {
                    return nil
                }

                return String(firstPart).trimmedNonEmpty
            }
            .last
    }

    private static func appendImageURL(
        _ rawURLString: String,
        baseURL: URL?,
        to urls: inout [URL],
        seenURLStrings: inout Set<String>
    ) {
        guard let url: URL = Self.imageURL(from: rawURLString, baseURL: baseURL) else {
            return
        }

        let urlString: String = url.absoluteString
        guard seenURLStrings.contains(urlString) == false else {
            return
        }

        seenURLStrings.insert(urlString)
        urls.append(url)
    }

    private static func imageURL(from rawURLString: String, baseURL: URL?) -> URL? {
        guard let normalizedURLString: String = Self.normalizedURLString(rawURLString) else {
            return nil
        }

        if normalizedURLString.hasPrefix("//"),
           let scheme: String = baseURL?.scheme {
            return URL(string: "\(scheme):\(normalizedURLString)")
        }

        return URL(string: normalizedURLString, relativeTo: baseURL)?.absoluteURL
    }

    private static func normalizedURLString(_ rawURLString: String) -> String? {
        var decoded: String = Self.decodedHTMLEntities(in: rawURLString)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u002f", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while let lastCharacter: Character = decoded.last,
              [")", "]", "}", ","].contains(lastCharacter) {
            decoded.removeLast()
        }

        guard decoded.isEmpty == false,
              decoded.hasPrefix("data:") == false else {
            return nil
        }

        return decoded
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

    private static func plainText(from html: String?) -> String? {
        guard let html: String = html else {
            return nil
        }

        let withoutTags: String = html.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let decoded: String = Self.decodedHTMLEntities(in: withoutTags)
        let collapsed: String = decoded
            .split(whereSeparator: { character in
                return character.isWhitespace
            })
            .joined(separator: " ")

        return collapsed.trimmedNonEmpty
    }

    private static func draftEditorTextBlocks(in html: String) -> [RSSContentPayload.Block] {
        let lines: [String] = Self.dataTextSpanContents(in: html).flatMap { spanText in
            Self.normalizedTextLines(from: spanText)
        }

        guard lines.isEmpty == false else {
            return []
        }

        return lines.enumerated().map { index, line in
            Self.block(
                kind: Self.paragraphBlockKind(html: line, text: line),
                text: line,
                imageURL: nil,
                index: index
            )
        }
    }

    private static func dataTextSpanContents(in html: String) -> [String] {
        var results: [String] = []
        var searchStart: String.Index = html.startIndex

        while let spanStart: Range<String.Index> = html.range(
            of: "<span",
            options: [.caseInsensitive],
            range: searchStart..<html.endIndex
        ) {
            guard let openEnd: Range<String.Index> = html.range(
                of: ">",
                range: spanStart.upperBound..<html.endIndex
            ) else {
                break
            }

            let openTag: String = String(html[spanStart.lowerBound...openEnd.lowerBound])
            searchStart = openEnd.upperBound

            guard Self.isDataTextSpan(openTag),
                  let closeRange: Range<String.Index> = html.range(
                    of: "</span>",
                    options: [.caseInsensitive],
                    range: openEnd.upperBound..<html.endIndex
                  ) else {
                continue
            }

            results.append(String(html[openEnd.upperBound..<closeRange.lowerBound]))
            searchStart = closeRange.upperBound
        }

        return results
    }

    private static func isDataTextSpan(_ openTag: String) -> Bool {
        let normalized: String = openTag
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .lowercased()

        return normalized.contains("data-text=\"true\"")
            || normalized.contains("data-text='true'")
    }

    private static func textOnlyBlocks(in html: String) -> [RSSContentPayload.Block] {
        guard let text: String = Self.plainTextPreservingLineBreaks(from: html) else {
            return []
        }

        let lines: [String] = Self.normalizedTextLines(from: text)

        guard lines.count > 1 else {
            return []
        }

        return lines.enumerated().map { index, line in
            Self.block(
                kind: Self.paragraphBlockKind(html: line, text: line),
                text: line,
                imageURL: nil,
                index: index
            )
        }
    }

    private static func plainTextPreservingLineBreaks(from html: String?) -> String? {
        guard let html: String = html else {
            return nil
        }

        let withStructuralLineBreaks: String = html
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</(?:p|div|h[1-6]|li|figure)>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)

        let decoded: String = Self.decodedHTMLEntities(in: withStructuralLineBreaks)

        return Self.normalizedTextLines(from: decoded).joined(separator: "\n").trimmedNonEmpty
    }

    private static func normalizedTextLines(from text: String) -> [String] {
        let decoded: String = Self.decodedHTMLEntities(in: text)
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\n")
        return decoded
            .components(separatedBy: .newlines)
            .compactMap { line in
                let normalizedLine: String? = line
                    .split(whereSeparator: { character in character.isWhitespace })
                    .joined(separator: " ")
                    .trimmedNonEmpty

                guard let normalizedLine: String,
                      Self.isDecorativeTextLine(normalizedLine) == false else {
                    return nil
                }

                return normalizedLine
            }
    }

    private static func decodedHTMLEntities(in text: String) -> String {
        return text
            .replacingOccurrences(of: "&#10;", with: "\n")
            .replacingOccurrences(of: "&#xA;", with: "\n")
            .replacingOccurrences(of: "&#xa;", with: "\n")
            .replacingOccurrences(of: "&#13;", with: "\n")
            .replacingOccurrences(of: "&#xD;", with: "\n")
            .replacingOccurrences(of: "&#xd;", with: "\n")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func firstInteger(pattern: String, in html: String) -> Int? {
        guard let value: String = Self.firstMatch(pattern: pattern, in: html) else {
            return nil
        }

        return Int(value.replacingOccurrences(of: ",", with: ""))
    }

    private static func firstMatch(pattern: String, in html: String) -> String? {
        return Self.matches(pattern: pattern, in: html).first
    }

    private static func matches(pattern: String, in html: String) -> [String] {
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range: NSRange = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let matchRange: Range<String.Index> = Range(match.range(at: 1), in: html) else {
                return nil
            }

            return String(html[matchRange])
        }
    }

    private static func isDecorativeTextLine(_ text: String) -> Bool {
        let decorativeLines: Set<String> = ["I", "|", "｜", "丨"]
        return decorativeLines.contains(text)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
