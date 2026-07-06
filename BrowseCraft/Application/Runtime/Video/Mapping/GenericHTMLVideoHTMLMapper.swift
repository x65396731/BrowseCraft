import Foundation
import SwiftSoup
import BrowseCraftCore

// 中文注释：GenericHTMLVideoHTMLMapper 只处理静态 HTML 中已经暴露列表、播放页或媒体 URL 的普通视频站。
struct GenericHTMLVideoHTMLMapper: VideoHTMLMapper {
    private enum Selectors {
        static let listItemGroups: [String] = [
            ".frame-block.thumb-block",
            "article",
            ".video-item, .video-card",
            ".movie, .vod",
            ".list-item",
            ".item, .card",
            ".video",
            "li"
        ]

        static let detailLinks: String = [
            ".thumb a[href]",
            ".thumb-under .title a[href]",
            "a[href*=\"/video\"]",
            "a[href*=\"play\"]",
            "a[href*=\"watch\"]",
            "a[href*=\"episode\"]",
            "a[href]"
        ].joined(separator: ", ")

        static let titleAttributes: String = [
            ".thumb-under .title a[title]",
            "a[title]",
            "img[alt]"
        ].joined(separator: ", ")

        static let titleTexts: String = [
            ".thumb-under .title a",
            ".title a",
            ".title",
            "h1",
            "h2",
            "h3",
            "a"
        ].joined(separator: ", ")

        static let covers: String = [
            "img[data-original]",
            "img[data-src]",
            "img[data-thumb]",
            "img[src]"
        ].joined(separator: ", ")

        static let latestTexts: String = [
            ".duration",
            ".latest",
            ".episode",
            ".remarks",
            ".tag",
            ".meta",
            ".metadata"
        ].joined(separator: ", ")

        static let episodeLinks: String = [
            "a[href*=\"play\"]",
            "a[href*=\"watch\"]",
            "a[href*=\"episode\"]",
            "a[href*=\"/video\"]"
        ].joined(separator: ", ")

        static let synopsis: String = [
            ".description",
            ".desc",
            ".summary",
            ".intro",
            ".synopsis",
            "[itemprop=\"description\"]"
        ].joined(separator: ", ")
    }

    private struct PlaybackCandidate {
        var url: URL?
        var kind: SourceVideoMediaKind
    }

    func mapList(
        html: String,
        definition: SourceDefinition,
        pageURL: URL
    ) throws -> [SourceContentItem] {
        let document: Document = try SwiftSoup.parse(html, pageURL.absoluteString)
        for selector: String in Selectors.listItemGroups {
            let elements: [Element] = try document.select(selector).array()
            let items: [SourceContentItem] = try self.mapListItems(
                elements,
                definition: definition,
                pageURL: pageURL
            )

            if items.isEmpty == false {
                return items
            }
        }

        return []
    }

    private func mapListItems(
        _ elements: [Element],
        definition: SourceDefinition,
        pageURL: URL
    ) throws -> [SourceContentItem] {
        var seenDetailURLs: Set<String> = Set<String>()
        var items: [SourceContentItem] = []

        for element: Element in elements {
            guard self.isLikelyContentItem(element),
                  let detailURL: URL = try self.detailURL(from: element, baseURL: pageURL),
                  let title: String = try self.title(from: element) else {
                continue
            }

            let detailKey: String = detailURL.absoluteString
            guard seenDetailURLs.contains(detailKey) == false else {
                continue
            }

            seenDetailURLs.insert(detailKey)
            items.append(
                SourceContentItem(
                    id: "\(definition.id).video.generic.\(self.stableID(from: detailURL))",
                    title: title,
                    detailURL: detailURL,
                    coverURL: try self.coverURL(from: element, baseURL: pageURL),
                    latestText: try self.latestText(from: element),
                    updatedAt: nil
                )
            )
        }

        return items
    }

    func mapDetail(
        html: String,
        definition: SourceDefinition,
        detailURL: URL
    ) throws -> VideoDetailContent {
        let document: Document = try SwiftSoup.parse(html, detailURL.absoluteString)
        let episode: VideoEpisode = VideoEpisode(
            id: self.stableID(from: detailURL),
            title: try self.title(from: document) ?? "Episode 1",
            playPageURL: detailURL
        )
        #if DEBUG
        print(
            "[BrowseCraftVideoMapping] genericHTML detail " +
            "source=\(definition.id) " +
            "detailURL=\(detailURL.absoluteString) " +
            "episodes=1 " +
            "episode=\(episode.id)"
        )
        #endif
        return VideoDetailContent(
            episodes: [
                episode
            ],
            synopsis: try self.synopsis(from: document),
            metadataRows: try self.metadataRows(from: document)
        )
    }

    func mapPlayback(
        html: String,
        definition: SourceDefinition,
        playPageURL: URL
    ) throws -> SourceVideoPlaybackReference {
        let document: Document = try SwiftSoup.parse(html, playPageURL.absoluteString)
        let candidate: PlaybackCandidate = self.playbackCandidate(
            from: html,
            document: document,
            baseURL: playPageURL
        )
        let title: String? = try self.title(from: document)
        let vodID: String = self.stableID(from: playPageURL)

        return SourceVideoPlaybackReference(
            vodID: vodID,
            sourceIndex: 1,
            episodeIndex: 1,
            episodeKey: SourceVideoPlaybackReference.episodeKey(
                vodID: vodID,
                sourceIndex: 1,
                episodeIndex: 1
            ),
            episodeTitle: title,
            playPageURL: playPageURL,
            candidateMediaURL: candidate.url,
            candidateMediaKind: candidate.kind,
            playbackRequestConfig: SourcePlaybackRequestConfig(
                headers: [
                    "Referer": playPageURL.absoluteString
                ],
                referer: playPageURL,
                userAgent: nil
            ),
            nextEpisodeURL: nil,
            previousEpisodeURL: nil,
            sourceName: "genericHTML",
            status: self.playbackStatus(
                mediaURL: candidate.url,
                mediaKind: candidate.kind,
                html: html
            )
        )
    }

    private func isLikelyContentItem(_ element: Element) -> Bool {
        guard let className: String = try? element.className().lowercased() else {
            return true
        }

        let excludedTokens: [String] = ["header", "footer", "nav", "menu", "pagination", "advert", "ads"]
        return excludedTokens.contains { token in
            return className.contains(token)
        } == false
    }

    private func detailURL(from element: Element, baseURL: URL) throws -> URL? {
        let links: [Element] = try element.select(Selectors.detailLinks).array()
        for link: Element in links {
            guard let href: String = try link.attr("href").trimmedNonEmpty,
                  self.isLikelyDetailHref(href),
                  let url: URL = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
                continue
            }

            return url
        }

        return nil
    }

    private func title(from element: Element) throws -> String? {
        let attributes: [Element] = try element.select(Selectors.titleAttributes).array()
        for attributeElement: Element in attributes {
            if let title: String = try attributeElement.attr("title").cleanedVideoText {
                return title
            }

            if let alt: String = try attributeElement.attr("alt").cleanedVideoText {
                return alt
            }
        }

        let texts: [Element] = try element.select(Selectors.titleTexts).array()
        for textElement: Element in texts {
            if let text: String = try textElement.text().cleanedVideoText {
                return text
            }
        }

        return nil
    }

    private func linkTitle(from element: Element) throws -> String? {
        return try element.attr("title").cleanedVideoText
            ?? element.text().cleanedVideoText
    }

    private func coverURL(from element: Element, baseURL: URL) throws -> URL? {
        let images: [Element] = try element.select(Selectors.covers).array()
        for image: Element in images {
            let value: String? = try image.attr("data-original").trimmedNonEmpty
                ?? image.attr("data-src").trimmedNonEmpty
                ?? image.attr("data-thumb").trimmedNonEmpty
                ?? image.attr("src").trimmedNonEmpty

            guard let value: String,
                  let url: URL = URL(string: value, relativeTo: baseURL)?.absoluteURL else {
                continue
            }

            return url
        }

        return nil
    }

    private func latestText(from element: Element) throws -> String? {
        let elements: [Element] = try element.select(Selectors.latestTexts).array()
        for element: Element in elements {
            if let text: String = try element.text().cleanedDetailText {
                return text
            }
        }

        return nil
    }

    private func synopsis(from document: Document) throws -> String? {
        let elements: [Element] = try document.select(Selectors.synopsis).array()
        return try elements
            .compactMap { element in
                return try element.text().cleanedDetailText
            }
            .first { text in
                return text.count >= 20
            }
    }

    private func metadataRows(from document: Document) throws -> [String] {
        let selectors: [String] = [
            ".metadata",
            ".meta",
            ".duration",
            "[itemprop=\"duration\"]",
            "[itemprop=\"uploadDate\"]"
        ]
        var rows: [String] = []

        for selector: String in selectors {
            let elements: [Element] = try document.select(selector).array()
            for element: Element in elements {
                guard let text: String = try element.text().cleanedVideoText,
                      rows.contains(text) == false else {
                    continue
                }

                rows.append(text)
            }
        }

        return Array(rows.prefix(6))
    }

    private func playbackCandidate(
        from html: String,
        document: Document,
        baseURL: URL
    ) -> PlaybackCandidate {
        let candidates: [String?] = [
            self.firstScriptArgument(html, functionName: "setVideoHLS"),
            self.firstScriptArgument(html, functionName: "setVideoUrlHigh"),
            self.firstScriptArgument(html, functionName: "setVideoUrlLow"),
            self.firstJSONLDContentURL(from: html),
            self.firstAttribute(in: document, selector: "video[src], source[src]", attribute: "src"),
            self.firstAttribute(in: document, selector: "iframe[src]", attribute: "src"),
            self.firstMediaURL(in: html, suffix: "m3u8"),
            self.firstMediaURL(in: html, suffix: "mp4")
        ]

        for candidate: String? in candidates {
            guard let candidate: String,
                  let url: URL = URL(string: candidate, relativeTo: baseURL)?.absoluteURL else {
                continue
            }

            return PlaybackCandidate(
                url: url,
                kind: self.mediaKind(for: url)
            )
        }

        return PlaybackCandidate(url: nil, kind: .unknown)
    }

    private func playbackStatus(
        mediaURL: URL?,
        mediaKind: SourceVideoMediaKind,
        html: String
    ) -> SourceVideoPlaybackStatus {
        let normalizedHTML: String = html.lowercased()

        if mediaURL != nil, mediaKind == .m3u8 || mediaKind == .mp4 {
            return .playable
        }

        if mediaURL != nil, mediaKind == .iframe {
            return .pageOnly
        }

        if normalizedHTML.contains("captcha") || normalizedHTML.contains("验证码") {
            return .restricted(.captchaOrAntiBot)
        }

        if normalizedHTML.contains("login") || normalizedHTML.contains("登录") {
            return .restricted(.requiresLogin)
        }

        if normalizedHTML.contains("vip") || normalizedHTML.contains("premium") || normalizedHTML.contains("会员") {
            return .restricted(.vipOnly)
        }

        return .failed(.mediaURLNotFound)
    }

    private func mediaKind(for url: URL?) -> SourceVideoMediaKind {
        guard let url: URL else {
            return .unknown
        }

        let path: String = url.path.lowercased()
        if path.hasSuffix(".m3u8") {
            return .m3u8
        }

        if path.hasSuffix(".mp4") {
            return .mp4
        }

        if path.contains("embed") || url.host?.lowercased().contains("iframe") == true {
            return .iframe
        }

        return .unknown
    }

    private func isLikelyDetailHref(_ href: String) -> Bool {
        let lowercased: String = href.lowercased()
        guard lowercased.hasPrefix("#") == false,
              lowercased.hasPrefix("javascript:") == false,
              lowercased.hasPrefix("mailto:") == false else {
            return false
        }

        return lowercased.contains("/video")
            || lowercased.contains("play")
            || lowercased.contains("watch")
            || lowercased.contains("episode")
    }

    private func isLikelyPlaybackURL(_ url: URL) -> Bool {
        return self.isLikelyDetailHref(url.absoluteString)
    }

    private func stableID(from url: URL) -> String {
        let value: String = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/", with: "-")

        return value.isEmpty ? "root" : value
    }

    private func firstScriptArgument(_ html: String, functionName: String) -> String? {
        return self.firstMatch(
            html,
            pattern: #"\#(functionName)\s*\(\s*['"]([^'"]+)['"]\s*\)"#
        )
    }

    private func firstJSONLDContentURL(from html: String) -> String? {
        return self.firstMatch(
            html,
            pattern: #""contentUrl"\s*:\s*"([^"]+)""#
        )
    }

    private func firstAttribute(
        in document: Document,
        selector: String,
        attribute: String
    ) -> String? {
        do {
            return try document.select(selector)
                .first()?
                .attr(attribute)
                .trimmedNonEmpty
        } catch {
            return nil
        }
    }

    private func firstMediaURL(in html: String, suffix: String) -> String? {
        return self.firstMatch(
            html,
            pattern: #"(https?:\/\/[^'"\s<>]+?\.\#(suffix)(?:\?[^'"\s<>]*)?)"#
        )
    }

    private func firstMatch(_ string: String, pattern: String) -> String? {
        guard let regex: NSRegularExpression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range: NSRange = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let result: NSTextCheckingResult = regex.firstMatch(in: string, range: range),
              result.numberOfRanges > 1,
              let swiftRange: Range<String.Index> = Range(result.range(at: 1), in: string) else {
            return nil
        }

        return String(string[swiftRange])
            .replacingOccurrences(of: "\\/", with: "/")
            .trimmedNonEmpty
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var cleanedVideoText: String? {
        let text: String = self.cleanedDetailTextValue
            .replacingOccurrences(
                of: #"\s+\d+\s*(min|sec|h)\b"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return text.isEmpty ? nil : text
    }

    var cleanedDetailText: String? {
        let text: String = self.cleanedDetailTextValue
        return text.isEmpty ? nil : text
    }

    private var cleanedDetailTextValue: String {
        return self
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .split(whereSeparator: { character in
                return character.isWhitespace
            })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
