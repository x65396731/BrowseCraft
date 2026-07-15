import Foundation

// 中文注释：RSSDetailHTMLParser 只解析 RSS detailURL 的网页正文，不参与 RSS feed XML 规则映射。
struct RSSDetailHTMLParser {
    struct DetailContent {
        var blocks: [RSSContentPayload.Block]
        var metadata: RSSContentPayload.Metadata
        var media: RSSContentPayload.Media?
    }

    static func detailContentBlocks(in html: String, pageURL: URL) -> [RSSContentPayload.Block] {
        return Self.detailContent(in: html, pageURL: pageURL).blocks
    }

    static func detailContent(in html: String, pageURL: URL) -> DetailContent {
        let articleHTML: String = Self.articleHTML(in: html) ?? html
        return DetailContent(
            blocks: Self.contentBlocks(in: articleHTML, baseURL: pageURL),
            metadata: Self.metadata(in: html, articleHTML: articleHTML),
            media: Self.media(in: html, articleHTML: articleHTML, pageURL: pageURL)
        )
    }

    private static func articleHTML(in html: String) -> String? {
        if let bbcLearningEnglishArticleHTML: String = Self.bbcLearningEnglishArticleHTML(in: html) {
            return bbcLearningEnglishArticleHTML
        }

        let markers: [String] = [
            #"<div class="topic_content""#,
            #"<div class='topic_content'"#,
            #"<div class="nfzm-content__fulltext"#,
            #"<div class='nfzm-content__fulltext"#,
            #"<div class="article--content"#,
            #"<div class='article--content"#,
            #"<div class="articlePage_content""#,
            #"<div class='articlePage_content'"#,
            #"class="articlePage_content""#,
            #"class='articlePage_content'"#
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
            #"<!--fulltext end-->"#,
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

    private static func bbcLearningEnglishArticleHTML(in html: String) -> String? {
        guard html.range(of: #"id="bbcle-content""#) != nil,
              let startRange: Range<String.Index> = html.range(of: #"<div id="bbcle-content""#) else {
            return nil
        }

        let tail: Substring = html[startRange.lowerBound...]
        let endMarkers: [String] = [
            #"<div class="widget widget-list widget-list-automatic""#,
            #"<div class='widget widget-list widget-list-automatic'"#
        ]

        if let endRange: Range<Substring.Index> = endMarkers.compactMap({ marker in
            tail.range(of: marker)
        }).min(by: { lhs, rhs in lhs.lowerBound < rhs.lowerBound }) {
            return String(tail[..<endRange.lowerBound])
        }

        return Self.balancedDivHTML(in: html, startingAt: startRange.lowerBound)
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
                if Self.isReactionImageTag(fullMatch, in: html, at: fullRange.lowerBound) {
                    continue
                }
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
                if Self.isDecorativeProfileImageTag(tag, in: html, at: tagRange.lowerBound)
                    || Self.isReactionImageTag(tag, in: html, at: tagRange.lowerBound) {
                    continue
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
                for attributeName in imageURLAttributes {
                    if let rawURLString: String = Self.attributeValue(named: attributeName, in: tag) {
                        Self.appendImageURL(
                            rawURLString,
                            baseURL: baseURL,
                            to: &urls,
                            seenURLStrings: &seenURLStrings
                        )
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
            #"//image\.gcores\.com/[^"'<>\s]+"#,
            #"https?:\\?/\\?/images\.infzm\.com/[^"'<>\s]+"#,
            #"//images\.infzm\.com/[^"'<>\s]+"#
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

    private static func isReactionImageTag(
        _ tag: String,
        in html: String,
        at tagStartIndex: String.Index
    ) -> Bool {
        if Self.attributeValue(named: "class", in: tag)?
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .contains("reaction-item-button") == true {
            return true
        }

        let prefixStart: String.Index = html.index(
            tagStartIndex,
            offsetBy: -min(600, html.distance(from: html.startIndex, to: tagStartIndex))
        )
        let prefix: String = String(html[prefixStart..<tagStartIndex])
        let directParentPattern: String = #"(?is)<[^>]+class=[\"'][^\"']*\breaction-item-button\b[^\"']*[\"'][^>]*>\s*$"#

        return prefix.range(of: directParentPattern, options: .regularExpression) != nil
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

    private static func media(in html: String, articleHTML: String, pageURL: URL) -> RSSContentPayload.Media? {
        return Self.mediaCandidates(in: articleHTML, pageURL: pageURL).first
            ?? Self.mediaCandidates(in: html, pageURL: pageURL).first
    }

    private static func mediaCandidates(in html: String, pageURL: URL) -> [RSSContentPayload.Media] {
        var candidates: [RSSContentPayload.Media] = []
        var seenURLStrings: Set<String> = []

        let mediaTagPattern: String = #"(?is)<(?:audio|video|source)\b[^>]*>"#
        if let mediaTagRegex: NSRegularExpression = try? NSRegularExpression(pattern: mediaTagPattern) {
            let range: NSRange = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in mediaTagRegex.matches(in: html, range: range) {
                guard let tagRange: Range<String.Index> = Range(match.range(at: 0), in: html) else {
                    continue
                }

                let tag: String = String(html[tagRange])
                let mimeType: String? = Self.attributeValue(named: "type", in: tag)
                let explicitKind: RSSContentPayload.MediaKind? = Self.explicitMediaKind(from: tag)
                for attributeName in ["src", "data-src", "data-url", "url"] {
                    guard let rawURLString: String = Self.attributeValue(named: attributeName, in: tag) else {
                        continue
                    }

                    Self.appendMediaCandidate(
                        rawURLString,
                        mimeType: mimeType,
                        explicitKind: explicitKind,
                        pageURL: pageURL,
                        to: &candidates,
                        seenURLStrings: &seenURLStrings
                    )
                }
            }
        }

        let embeddedMediaURLPattern: String = #"https?:\\?/\\?/[^"'<>\s]+?\.(?:mp3|m4a|aac|ogg|oga|wav|flac|mp4|m4v|webm|mov|m3u8)(?:\?[^"'<>\s]*)?"#
        if let embeddedMediaURLRegex: NSRegularExpression = try? NSRegularExpression(
            pattern: embeddedMediaURLPattern,
            options: [.caseInsensitive]
        ) {
            let range: NSRange = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in embeddedMediaURLRegex.matches(in: html, range: range) {
                guard let urlRange: Range<String.Index> = Range(match.range(at: 0), in: html) else {
                    continue
                }

                Self.appendMediaCandidate(
                    String(html[urlRange]),
                    mimeType: nil,
                    explicitKind: nil,
                    pageURL: pageURL,
                    to: &candidates,
                    seenURLStrings: &seenURLStrings
                )
            }
        }

        return candidates
    }

    private static func appendMediaCandidate(
        _ rawURLString: String,
        mimeType: String?,
        explicitKind: RSSContentPayload.MediaKind?,
        pageURL: URL,
        to candidates: inout [RSSContentPayload.Media],
        seenURLStrings: inout Set<String>
    ) {
        guard let normalizedURLString: String = Self.normalizedURLString(rawURLString) else {
            return
        }

        let url: URL?
        if normalizedURLString.hasPrefix("//") {
            let scheme: String = pageURL.scheme?.lowercased() == "http" ? "https" : (pageURL.scheme ?? "https")
            url = Self.absoluteURL(from: "\(scheme):\(normalizedURLString)", baseURL: nil)
        } else {
            url = Self.absoluteURL(from: normalizedURLString, baseURL: pageURL)
        }

        guard let url: URL,
              seenURLStrings.contains(url.absoluteString) == false else {
            return
        }

        let kind: RSSContentPayload.MediaKind?
        if let explicitKind: RSSContentPayload.MediaKind = explicitKind {
            kind = explicitKind
        } else {
            kind = RSSMediaClassifier.directMediaKind(mimeType: mimeType, url: url)
        }

        guard let kind: RSSContentPayload.MediaKind = kind else {
            return
        }

        seenURLStrings.insert(url.absoluteString)
        candidates.append(
            RSSContentPayload.Media(
                kind: kind,
                playbackMode: .directMedia,
                url: url.absoluteString,
                mimeType: mimeType?.trimmedNonEmpty ?? RSSMediaClassifier.mimeType(for: url),
                duration: nil,
                posterURL: nil,
                sourcePageURL: pageURL.absoluteString
            )
        )
    }

    private static func explicitMediaKind(from tag: String) -> RSSContentPayload.MediaKind? {
        let lowercasedTag: String = tag.lowercased()
        if lowercasedTag.hasPrefix("<audio") {
            return .audio
        }
        if lowercasedTag.hasPrefix("<video") {
            return .video
        }

        return nil
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

        if normalizedURLString.hasPrefix("//") {
            let scheme: String = baseURL?.scheme?.lowercased() == "http" ? "https" : (baseURL?.scheme ?? "https")
            return Self.absoluteURL(from: "\(scheme):\(normalizedURLString)", baseURL: nil)
        }

        return Self.absoluteURL(from: normalizedURLString, baseURL: baseURL)
    }

    private static func absoluteURL(from string: String, baseURL: URL?) -> URL? {
        if let url: URL = URL(string: string, relativeTo: baseURL)?.absoluteURL {
            return url
        }

        guard let encodedString: String = string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        return URL(string: encodedString, relativeTo: baseURL)?.absoluteURL
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
              decoded.hasPrefix("data:") == false,
              decoded.hasPrefix("blob:") == false,
              decoded != "#",
              decoded.lowercased() != "about:blank",
              Self.isTemplateImageURL(decoded) == false else {
            return nil
        }

        return decoded
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
