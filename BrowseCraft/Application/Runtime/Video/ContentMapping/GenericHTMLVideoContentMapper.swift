import Foundation
import SwiftSoup
import BrowseCraftCore

// 中文注释：GenericHTMLVideoContentMapper 处理通用视频 HTML/DOM；HTML 可来自静态 HTTP 或 WebView 渲染。
struct GenericHTMLVideoContentMapper: VideoContentMapper {
    private static let playbackUserAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private enum Selectors {
        static let listItemGroups: [String] = [
            ".frame-block.thumb-block",
            "article",
            "[data-testid*=\"video\"], [data-testid*=\"card\"]",
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
            "a[href*=\"/videos/\"]",
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
            "h4",
            "a"
        ].joined(separator: ", ")

        static let covers: String = [
            "img[data-original]",
            "img[data-src]",
            "img[data-srcset]",
            "img[data-thumb]",
            "[data-image]",
            "[data-img]",
            "[data-poster]",
            "[poster]",
            "[style*=\"background-image\"]",
            "meta[itemprop=\"thumbnailUrl\"][content]",
            "link[itemprop=\"thumbnailUrl\"][href]",
            "img[src]",
            "img[srcset]",
            "source[srcset]"
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
            "a[href*=\"/video\"]",
            "a[href*=\"/videos/\"]"
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

    private let lexicon: VideoDetectionLexicon
    private let noiseFilter: any SourceContentNoiseFiltering

    init(
        lexicon: VideoDetectionLexicon = .default,
        noiseFilter: any SourceContentNoiseFiltering = SourceContentNoiseFilter()
    ) {
        self.lexicon = lexicon
        self.noiseFilter = noiseFilter
    }

    func mapList(
        html: String,
        definition: SourceDefinition,
        pageURL: URL
    ) throws -> [SourceContentItem] {
        let document: Document = try SwiftSoup.parse(html, pageURL.absoluteString)
        let pageCoverURLs: [String: URL] = self.pageCoverURLMap(from: html, pageURL: pageURL)
        for selector: String in Selectors.listItemGroups {
            let elements: [Element] = try document.select(selector).array()
            let items: [SourceContentItem] = try self.mapListItems(
                elements,
                definition: definition,
                pageURL: pageURL,
                pageCoverURLs: pageCoverURLs
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
        pageURL: URL,
        pageCoverURLs: [String: URL]
    ) throws -> [SourceContentItem] {
        var seenDetailURLs: Set<String> = Set<String>()
        var items: [SourceContentItem] = []

        for element: Element in elements {
            guard self.isLikelyContentItem(element),
                  let detailURL: URL = try self.detailURL(from: element, baseURL: pageURL),
                  self.isLikelyDetailURL(detailURL, pageURL: pageURL),
                  let title: String = try self.title(from: element),
                  self.isLanguageSwitchItem(title: title, detailURL: detailURL, pageURL: pageURL) == false else {
                continue
            }

            let noiseDecision: SourceContentNoiseDecision = self.noiseFilter.decision(
                for: try self.noiseCandidate(
                    from: element,
                    title: title,
                    url: detailURL,
                    context: .listItem
                )
            )
            guard noiseDecision.action != .discard else {
                continue
            }

            let detailKey: String = detailURL.absoluteString
            guard seenDetailURLs.contains(detailKey) == false else {
                continue
            }

            let elementCoverURL: URL? = try self.coverURL(from: element, baseURL: pageURL)
            let fallbackCoverURL: URL? = pageCoverURLs[self.normalizedURLKey(detailURL)]
            let coverURL: URL? = elementCoverURL ?? fallbackCoverURL
            #if DEBUG
            if coverURL == nil {
                print(
                    "[BrowseCraftVideoMapping] genericHTML list missing-cover " +
                    "source=\(definition.id) " +
                    "title=\(title) " +
                    "detailURL=\(detailURL.absoluteString)"
                )
            }
            #endif
            seenDetailURLs.insert(detailKey)
            items.append(
                SourceContentItem(
                    id: "\(definition.id).video.generic.\(self.stableID(from: detailURL))",
                    title: title,
                    detailURL: detailURL,
                    coverURL: coverURL,
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
        let candidate: VideoPlaybackCandidate = self.playbackCandidate(
            from: html,
            document: document,
            baseURL: playPageURL
        )
        let resolution: VideoPlaybackResolution = self.playbackResolution(
            candidate: candidate,
            playPageURL: playPageURL,
            html: html,
            definition: definition
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
            candidateMediaURL: resolution.candidateMediaURL,
            candidateMediaKind: resolution.candidateMediaKind,
            playbackRequestConfig: resolution.playbackRequestConfig,
            nextEpisodeURL: nil,
            previousEpisodeURL: nil,
            sourceName: "genericHTML",
            status: resolution.status
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
            guard let value: String = try self.coverURLString(from: image),
                  let url: URL = URL(string: value, relativeTo: baseURL)?.absoluteURL else {
                continue
            }

            return url
        }

        return nil
    }

    private func coverURLString(from image: Element) throws -> String? {
        let directAttributes: [String] = [
            "data-original",
            "data-src",
            "data-thumb",
            "data-image",
            "data-img",
            "data-poster",
            "poster",
            "content",
            "href",
            "src"
        ]
        for attribute: String in directAttributes {
            if let value: String = try image.attr(attribute).trimmedNonEmpty {
                return value
            }
        }

        if let value: String = self.firstSrcsetURL(try image.attr("data-srcset")) {
            return value
        }

        if let value: String = self.firstSrcsetURL(try image.attr("srcset")) {
            return value
        }

        return self.firstStyleURL(try image.attr("style"))
    }

    private func firstSrcsetURL(_ srcset: String) -> String? {
        return srcset
            .split(separator: ",")
            .lazy
            .compactMap { candidate -> String? in
                return candidate
                    .split(whereSeparator: { character in
                        return character.isWhitespace
                    })
                    .first
                    .map(String.init)?
                    .trimmedNonEmpty
            }
            .first
    }

    private func firstStyleURL(_ style: String) -> String? {
        return self.firstMatch(
            style,
            pattern: #"url\((?:'|")?([^)'"]+)(?:'|")?\)"#
        )
    }

    private func pageCoverURLMap(from html: String, pageURL: URL) -> [String: URL] {
        let normalizedHTML: String = self.normalizedEmbeddedHTML(html)
        let imageMatches: [TextURLMatch] = self.arteImageURLMatches(in: normalizedHTML)
        guard imageMatches.isEmpty == false else {
            return [:]
        }

        let detailMatches: [TextURLMatch] = self.detailURLMatches(in: normalizedHTML, pageURL: pageURL)
        var map: [String: URL] = [:]
        for detailMatch: TextURLMatch in detailMatches {
            let key: String = self.normalizedURLKey(detailMatch.url)
            guard map[key] == nil,
                  let imageURL: URL = self.nearestImageURL(to: detailMatch, images: imageMatches) else {
                continue
            }

            map[key] = imageURL
        }

        return map
    }

    private func normalizedEmbeddedHTML(_ html: String) -> String {
        return html
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private func arteImageURLMatches(in text: String) -> [TextURLMatch] {
        return self.urlMatches(
            in: text,
            pattern: #"https?:\/\/api-cdn\.arte\.tv\/img\/v2\/image\/[^"',}\\\s<>]+"#,
            baseURL: nil
        )
    }

    private func detailURLMatches(in text: String, pageURL: URL) -> [TextURLMatch] {
        let absolutePattern: String = #"https?:\/\/www\.arte\.tv\/en\/videos\/(?:RC-\d+|\d{4,}-\d{3}-[A-Z])\/[^"',}\\\s<>]+"#
        let relativePattern: String = #"\/en\/videos\/(?:RC-\d+|\d{4,}-\d{3}-[A-Z])\/[^"',}\\\s<>]+"#
        return self.urlMatches(in: text, pattern: absolutePattern, baseURL: pageURL)
            + self.urlMatches(in: text, pattern: relativePattern, baseURL: pageURL)
    }

    private func urlMatches(
        in text: String,
        pattern: String,
        baseURL: URL?
    ) -> [TextURLMatch] {
        guard let regex: NSRegularExpression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let nsRange: NSRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let results: [NSTextCheckingResult] = regex.matches(in: text, range: nsRange)
        return results.compactMap { result -> TextURLMatch? in
            guard let range: Range<String.Index> = Range(result.range, in: text) else {
                return nil
            }

            let rawValue: String = String(text[range])
            guard let url: URL = URL(string: rawValue, relativeTo: baseURL)?.absoluteURL else {
                return nil
            }

            return TextURLMatch(location: result.range.location, url: url)
        }
    }

    private func nearestImageURL(
        to detail: TextURLMatch,
        images: [TextURLMatch]
    ) -> URL? {
        let maxDistance: Int = 5_000
        var bestMatch: TextURLMatch?
        var bestDistance: Int = Int.max

        for image in images {
            let distance: Int = abs(image.location - detail.location)
            guard distance < bestDistance,
                  distance <= maxDistance else {
                continue
            }

            bestDistance = distance
            bestMatch = image
        }

        return bestMatch?.url
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
    ) -> VideoPlaybackCandidate {
        let candidates: [String?] = [
            self.firstScriptArgument(html, functionName: "setVideoHLS"),
            self.firstScriptArgument(html, functionName: "setVideoUrlHigh"),
            self.firstScriptArgument(html, functionName: "setVideoUrlLow"),
            self.firstJSONLDContentURL(from: html),
            self.firstVimeoProgressiveMP4(from: html),
            self.firstAttribute(in: document, selector: "video[src], source[src]", attribute: "src"),
            self.firstMediaURL(in: html, suffix: "m3u8"),
            self.firstMediaURL(in: html, suffix: "mp4")
        ]

        for candidate: String? in candidates {
            guard let candidate: String,
                  let url: URL = URL(string: candidate, relativeTo: baseURL)?.absoluteURL else {
                continue
            }

            return VideoPlaybackCandidate(
                url: url,
                kind: self.mediaKind(for: url)
            )
        }

        if let iframeSource: String = self.firstPlaybackFrameSource(
            html: html,
            document: document,
            baseURL: baseURL
        ),
           let iframePlayerURL: URL = URL(string: iframeSource, relativeTo: baseURL)?.absoluteURL {
            return VideoPlaybackCandidate(url: iframePlayerURL, kind: .iframePlayer)
        }

        if self.mediaKind(for: baseURL) == .iframePlayer {
            return VideoPlaybackCandidate(url: baseURL, kind: .iframePlayer)
        }

        return VideoPlaybackCandidate(url: nil, kind: .unknown)
    }

    private func playbackResolution(
        candidate: VideoPlaybackCandidate,
        playPageURL: URL,
        html: String,
        definition: SourceDefinition
    ) -> VideoPlaybackResolution {
        if let resolution: VideoPlaybackResolution = IframePlayerCandidateResolver().resolve(
            candidate: candidate,
            playPageURL: playPageURL,
            html: html
        ) {
            return resolution
        }

        let refererURL: URL = self.playbackRefererURL(for: playPageURL)
        return VideoPlaybackResolution(
            candidateMediaURL: candidate.url,
            candidateMediaKind: candidate.kind,
            playbackRequestConfig: SourcePlaybackRequestConfig(
                headers: [
                    "Referer": refererURL.absoluteString,
                    "User-Agent": Self.playbackUserAgent
                ],
                referer: refererURL,
                userAgent: Self.playbackUserAgent
            ),
            status: self.playbackStatus(
                mediaURL: candidate.url,
                mediaKind: candidate.kind,
                html: html,
                definition: definition
            )
        )
    }

    private func playbackStatus(
        mediaURL: URL?,
        mediaKind: SourceVideoMediaKind,
        html: String,
        definition: SourceDefinition
    ) -> SourceVideoPlaybackStatus {
        if mediaURL != nil, mediaKind == .m3u8 || mediaKind == .mp4 {
            return .playable
        }

        if mediaURL != nil, mediaKind == .iframePlayer {
            return .pageOnly
        }

        if self.lexicon.containsMarker(in: html, category: .captchaRestriction) {
            return .restricted(.captchaOrAntiBot)
        }

        if self.lexicon.containsMarker(in: html, category: .accountRestriction) {
            return .restricted(.requiresLogin)
        }

        if self.lexicon.containsMarker(in: html, category: .payRestriction) {
            return .restricted(.vipOnly)
        }

        if self.requiresRenderedWebPlayback(definition: definition) {
            return .pageOnly
        }

        return .failed(.mediaURLNotFound)
    }

    private func requiresRenderedWebPlayback(definition: SourceDefinition) -> Bool {
        guard let videoDefinition: VideoSourceDefinition = definition.video else {
            return false
        }

        return videoDefinition.sharedRequest?.needsWebView == true
            || videoDefinition.playRequest?.needsWebView == true
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

        let host: String = url.host?.lowercased() ?? ""
        if path.contains("embed")
            || host.contains("iframe")
            || host.hasPrefix("player.") {
            return .iframePlayer
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
            || lowercased.contains("/videos/")
            || lowercased.contains("play")
            || lowercased.contains("watch")
            || lowercased.contains("episode")
    }

    private func isLikelyDetailURL(_ url: URL, pageURL: URL) -> Bool {
        let pagePath: String = self.normalizedDirectoryPath(pageURL.path.lowercased())
        let detailPath: String = self.normalizedDirectoryPath(url.path.lowercased())
        guard pagePath != "/",
              detailPath.hasPrefix(pagePath),
              detailPath != pagePath else {
            return true
        }

        let suffix: String = String(detailPath.dropFirst(pagePath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let segments: [Substring] = suffix.split(separator: "/")
        guard segments.count == 1 else {
            return true
        }

        return self.isConcreteVideoIDSegment(String(segments[0]))
    }

    private func isLanguageSwitchItem(
        title: String,
        detailURL: URL,
        pageURL: URL
    ) -> Bool {
        guard title.range(
            of: #"^[\p{L}\p{M}\s]+ \([A-Z]{2}\)$"#,
            options: [.regularExpression]
        ) != nil else {
            return false
        }

        let pageLanguage: String? = self.languagePathSegment(from: pageURL)
        let detailLanguage: String? = self.languagePathSegment(from: detailURL)
        if let pageLanguage: String,
           let detailLanguage: String,
           pageLanguage != detailLanguage {
            return true
        }

        return self.isCategoryRootURL(detailURL)
    }

    private func languagePathSegment(from url: URL) -> String? {
        let segments: [String] = url.pathComponents.filter { component in
            return component != "/"
        }
        guard let language: String = segments.first,
              language.count == 2 else {
            return nil
        }

        return language.lowercased()
    }

    private func isCategoryRootURL(_ url: URL) -> Bool {
        let segments: [String] = url.pathComponents.filter { component in
            return component != "/"
        }
        guard segments.count >= 3,
              segments[1].lowercased() == "videos" else {
            return false
        }

        return self.isConcreteVideoIDSegment(segments[2]) == false
    }

    private func normalizedDirectoryPath(_ path: String) -> String {
        let trimmed: String = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "/" : "/\(trimmed)/"
    }

    private func normalizedURLKey(_ url: URL) -> String {
        guard var components: URLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased()
        }

        components.fragment = nil
        let value: String = components.url?.absoluteString ?? url.absoluteString
        return value
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    private func isConcreteVideoIDSegment(_ segment: String) -> Bool {
        if segment.range(
            of: #"^\d{4,}-\d{3}-[a-z]$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }

        return false
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

    private func firstVimeoProgressiveMP4(from html: String) -> String? {
        return self.firstMatch(
            html,
            pattern: #""progressive"\s*:\s*\[[\s\S]*?"url"\s*:\s*"([^"]+?\.mp4[^"]*)"#
        )
    }

    private func firstJSONLDEmbedURL(from html: String) -> String? {
        return self.firstMatch(
            html,
            pattern: #""embedUrl"\s*:\s*"([^"]+)""#
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

    private func firstPlaybackFrameSource(
        html: String,
        document: Document,
        baseURL: URL
    ) -> String? {
        do {
            let metaSelectors: [String] = [
                "meta[property=og:video:url][content]",
                "meta[property=og:video:secure_url][content]",
                "meta[name=twitter:player][content]",
                "meta[name=twitter:player][value]"
            ]
            for selector: String in metaSelectors {
                let metas: [Element] = try document.select(selector).array()
                for meta: Element in metas {
                    let content: String? = try meta.attr("content").trimmedNonEmpty
                    let value: String? = try meta.attr("value").trimmedNonEmpty
                    guard let source: String = content ?? value,
                          let url: URL = URL(string: source, relativeTo: baseURL)?.absoluteURL,
                          self.mediaKind(for: url) == .iframePlayer else {
                        continue
                    }

                    return source
                }
            }

            if let embedURLString: String = self.firstJSONLDEmbedURL(from: html),
               let embedURL: URL = URL(string: embedURLString, relativeTo: baseURL)?.absoluteURL,
               self.mediaKind(for: embedURL) == .iframePlayer {
                return embedURLString
            }

            let frames: [Element] = try document.select("iframe[src], embed[src]").array()
            for frame: Element in frames {
                guard let source: String = try frame.attr("src").trimmedNonEmpty,
                      let url: URL = URL(string: source, relativeTo: baseURL)?.absoluteURL else {
                    continue
                }

                let decision: SourceContentNoiseDecision = self.noiseFilter.decision(
                    for: try self.noiseCandidate(
                        from: frame,
                        title: self.linkTitle(from: frame),
                        url: url,
                        context: .playbackCandidate
                    )
                )
                guard decision.action != .discard else {
                    continue
                }

                return source
            }

            return nil
        } catch {
            return nil
        }
    }

    private func noiseCandidate(
        from element: Element,
        title: String?,
        url: URL?,
        context: SourceContentNoiseContext
    ) throws -> SourceContentNoiseCandidate {
        return SourceContentNoiseCandidate(
            title: title,
            url: url,
            text: try element.text().trimmedNonEmpty,
            cssClass: try element.className().trimmedNonEmpty,
            elementID: element.id().trimmedNonEmpty,
            tagName: element.tagName().trimmedNonEmpty,
            attributes: try self.noiseAttributes(from: element),
            sourceKind: .video,
            context: context
        )
    }

    private func noiseAttributes(from element: Element) throws -> [String: String] {
        let names: [String] = [
            "href",
            "src",
            "title",
            "alt",
            "aria-label",
            "data-src",
            "data-original",
            "data-thumb",
            "role"
        ]
        var attributes: [String: String] = [:]

        for name: String in names {
            if let value: String = try element.attr(name).trimmedNonEmpty {
                attributes[name] = value
            }
        }

        return attributes
    }

    private func firstMediaURL(in html: String, suffix: String) -> String? {
        return self.firstMatch(
            html,
            pattern: #"(https?:\/\/[^'"\s<>]+?\.\#(suffix)(?:\?[^'"\s<>]*)?)"#
        )
    }

    private func playbackRefererURL(for playPageURL: URL) -> URL {
        guard playPageURL.host?.lowercased() == "player.vimeo.com" else {
            return playPageURL
        }

        let components: [String] = playPageURL.pathComponents.filter { component in
            component != "/"
        }
        guard components.count >= 2,
              components[0] == "video",
              let url: URL = URL(string: "https://vimeo.com/\(components[1])") else {
            return playPageURL
        }

        return url
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
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmedNonEmpty
    }
}

private struct TextURLMatch {
    let location: Int
    let url: URL
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
