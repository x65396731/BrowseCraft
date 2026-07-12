import Foundation
import SwiftSoup
import BrowseCraftCore

// 中文注释：MacCMSVideoContentMapper 只处理 MacCMS 常见 HTML/DOM，不处理 VIP/DRM/反爬绕过。
struct MacCMSVideoContentMapper: VideoContentMapper {
    private enum Defaults {
        // Limit detail metadata summary rows only; this does not cap discovered category tabs.
        static let maxMetadataRows: Int = 6
    }

    private enum Selectors {
        static let listItems: String = [
            ".ewave-vodlist__box",
            ".stui-vodlist__box",
            ".stui-vodlist__item",
            ".myui-vodlist__box",
            ".module-item",
            ".module-card-item",
            ".fed-list-item"
        ].joined(separator: ", ")

        static let detailLinks: String = [
            "a.thumb-link[href^=\"/voddetail/\"]",
            "h4 a[href^=\"/voddetail/\"]",
            ".module-item-pic[href^=\"/voddetail/\"]",
            ".module-card-item-title[href^=\"/voddetail/\"]",
            "a.fed-list-pics[href*=\"/voddetail/\"]",
            "a.fed-list-title[href*=\"/voddetail/\"]",
            "a[href*=\"/voddetail/\"]"
        ].joined(separator: ", ")

        static let titleAttributes: String = [
            ".ewave-vodlist__thumb[title]",
            ".stui-vodlist__thumb[title]",
            ".myui-vodlist__thumb[title]",
            ".module-item-pic[title]",
            ".fed-list-pics[title]",
            ".fed-list-title[title]"
        ].joined(separator: ", ")

        static let titleTexts: String = [
            ".ewave-vodlist__detail h4 a",
            ".stui-vodlist__detail h4 a",
            ".myui-vodlist__detail h4 a",
            ".module-card-item-title",
            ".fed-list-title h4",
            ".fed-list-title",
            ".cinema_title",
            "h4.title a"
        ].joined(separator: ", ")

        static let covers: String = [
            ".ewave-vodlist__thumb[data-original]",
            ".stui-vodlist__thumb[data-original]",
            ".myui-vodlist__thumb[data-original]",
            ".module-item-pic[data-src]",
            ".fed-list-pics[data-original]",
            ".fed-list-pics[data-src]",
            "img[data-original]",
            "img[data-src]",
            "img[src]"
        ].joined(separator: ", ")

        static let latestTexts: String = [
            ".pic-text.text-right",
            ".pic-text",
            ".module-item-note",
            ".module-item-text",
            ".fed-list-remarks"
        ].joined(separator: ", ")

        static let episodeLinks: String = [
            ".ewave-content__playlist a[href^=\"/vodplay/\"]",
            ".ewave-content__playlist a[href*=\"/vodplay/\"]",
            ".stui-content__playlist a[href^=\"/vodplay/\"]",
            ".stui-content__playlist a[href*=\"/vodplay/\"]",
            ".myui-content__list a[href^=\"/vodplay/\"]",
            ".myui-content__list a[href*=\"/vodplay/\"]",
            ".module-play-list a[href^=\"/vodplay/\"]",
            ".module-play-list a[href*=\"/vodplay/\"]",
            ".fed-play-item a[href*=\"/vodplay/\"]",
            ".fed-part-rows a[href*=\"/vodplay/\"]"
        ].joined(separator: ", ")

        static let playerTitles: String = [
            ".ewave-player__detail h1.title a",
            ".stui-player__detail h1.title a",
            ".myui-player__detail h1.title a",
            ".fed-player-info h1",
            ".fed-play-title",
            "h1.title"
        ].joined(separator: ", ")
    }

    private let lexicon: VideoDetectionLexicon

    init(lexicon: VideoDetectionLexicon = .default) {
        self.lexicon = lexicon
    }

    private struct PlayerPayload: Decodable {
        let link: String?
        let link_next: String?
        let link_pre: String?
        let url: String?
        let from: String?
        let id: String?
        let sid: Int?
        let nid: Int?
    }

    func mapList(
        html: String,
        definition: SourceDefinition,
        pageURL: URL
    ) throws -> [SourceContentItem] {
        let document: Document = try SwiftSoup.parse(html, pageURL.absoluteString)
        let elements: [Element] = try document.select(Selectors.listItems).array()
        var seenIDs: Set<String> = Set<String>()
        var items: [SourceContentItem] = []

        for element: Element in elements {
            guard try self.shouldIncludeListItem(element) else {
                continue
            }

            guard let detailURL: URL = try self.detailURL(from: element, baseURL: pageURL),
                  let vodID: String = self.vodID(from: detailURL) else {
                continue
            }

            let title: String = try self.title(from: element) ?? "Untitled Video"
            let itemID: String = "\(definition.id).video.\(vodID)"
            guard seenIDs.contains(itemID) == false else {
                continue
            }

            seenIDs.insert(itemID)
            items.append(
                SourceContentItem(
                    id: itemID,
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

    private func shouldIncludeListItem(_ element: Element) throws -> Bool {
        let classes: [String] = try element.attr("class")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard classes.contains("fed-list-item") else {
            return true
        }

        if try element.attr("id").hasPrefix("listid_") {
            return true
        }

        let titleLinks: [Element] = try element.select("a.fed-list-title[href*=\"/voddetail/\"]")
            .array()
        return titleLinks.isEmpty == false
    }

    func mapDetail(
        html: String,
        definition: SourceDefinition,
        detailURL: URL
    ) throws -> VideoDetailContent {
        let document: Document = try SwiftSoup.parse(html, detailURL.absoluteString)
        let usesVfedPlayItems: Bool = try document.select(".fed-play-item").array().isEmpty == false
        let entries: [VfedEpisodeEntry] = try self.episodeEntries(from: document)
        var seenIDs: Set<String> = Set<String>()
        var episodes: [VideoEpisode] = []

        for entry: VfedEpisodeEntry in entries {
            let element: Element = entry.element
            guard let href: String = try element.attr("href").trimmedNonEmpty,
                  let url: URL = URL(string: href, relativeTo: detailURL)?.absoluteURL,
                  let route: VideoPlayRoute = self.playRoute(from: url.path) else {
                continue
            }

            let episodeID: String = SourceVideoPlaybackReference.episodeKey(
                vodID: route.vodID,
                sourceIndex: route.sourceIndex,
                episodeIndex: route.episodeIndex
            )
            guard seenIDs.contains(episodeID) == false else {
                continue
            }

            let title: String = try element.text().trimmedNonEmpty ?? "Episode \(route.episodeIndex)"
            let displayTitle: String = entry.lineTitle.map { "\($0) - \(title)" } ?? title
            seenIDs.insert(episodeID)
            episodes.append(
                VideoEpisode(
                    id: episodeID,
                    title: displayTitle,
                    playPageURL: url
                )
            )
        }

        return VideoDetailContent(
            episodes: usesVfedPlayItems ? episodes : self.sortedEpisodes(episodes),
            synopsis: try self.synopsis(from: document),
            metadataRows: try self.metadataRows(from: document)
        )
    }

    private func episodeEntries(from document: Document) throws -> [VfedEpisodeEntry] {
        let playItems: [Element] = try document.select(".fed-play-item").array()
        guard playItems.isEmpty == false else {
            return try document.select(Selectors.episodeLinks)
                .array()
                .filter { element in
                    return try self.shouldIncludeEpisodeLink(element)
                }
                .map { element in
                    return VfedEpisodeEntry(element: element, lineTitle: nil)
                }
        }

        let rankedPlayItems: [(offset: Int, element: Element)] = try playItems.enumerated()
            .map { pair in
                return (offset: pair.offset, element: pair.element)
            }
            .sorted { lhs, rhs in
                let lhsScore: Int = try self.vfedPlayItemPreferenceScore(lhs.element)
                let rhsScore: Int = try self.vfedPlayItemPreferenceScore(rhs.element)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }

                return lhs.offset < rhs.offset
            }

        var entries: [VfedEpisodeEntry] = []
        for rankedPlayItem in rankedPlayItems {
            let playItem: Element = rankedPlayItem.element
            let elements: [Element] = try self.vfedEpisodeElements(in: playItem)
            let title: String = try self.vfedPlayItemTitle(playItem)
            let score: Int = try self.vfedPlayItemPreferenceScore(playItem)
            #if DEBUG
            print(
                "[BrowseCraftMacCMSVfedEpisodes] candidate " +
                "title=\(title) count=\(elements.count) score=\(score) " +
                "first=\(try elements.first?.attr("href") ?? "nil")"
            )
            #endif

            for element: Element in elements {
                guard try self.shouldIncludeEpisodeLink(element) else {
                    continue
                }

                entries.append(
                    VfedEpisodeEntry(
                        element: element,
                        lineTitle: self.normalizedVfedPlayItemTitle(title)
                    )
                )
            }
        }

        #if DEBUG
        print(
            "[BrowseCraftMacCMSVfedEpisodes] selected " +
            "count=\(entries.count) " +
            "first=\(try entries.first?.element.attr("href") ?? "nil")"
        )
        #endif
        return entries
    }

    private func vfedEpisodeElements(in playItem: Element) throws -> [Element] {
        var directListElements: [Element] = []
        for child: Element in playItem.children().array() {
            guard child.tagNameNormal() == "ul",
                  child.hasClass("fed-part-rows"),
                  child.hasClass("fed-drop-head") == false else {
                continue
            }

            directListElements.append(
                contentsOf: try child.select("a[href*=\"/vodplay/\"]").array()
            )
        }

        if directListElements.isEmpty == false {
            return try self.sortedVfedEpisodeElements(
                self.deduplicatedVfedEpisodeElements(directListElements)
            )
        }

        let fallbackElements: [Element] = try playItem.select("a[href*=\"/vodplay/\"]")
            .array()
            .filter { anchor in
                return self.isElement(anchor, insideOwnVfedPlayItem: playItem)
            }
        return try self.sortedVfedEpisodeElements(
            self.deduplicatedVfedEpisodeElements(fallbackElements)
        )
    }

    private func deduplicatedVfedEpisodeElements(_ elements: [Element]) throws -> [Element] {
        var seenRoutes: Set<String> = Set<String>()
        var uniqueElements: [Element] = []

        for element: Element in elements {
            guard let href: String = try element.attr("href").trimmedNonEmpty else {
                continue
            }

            let path: String = URL(string: href)?.path ?? href
            let routeKey: String
            if let route: VideoPlayRoute = self.playRoute(from: path) {
                routeKey = SourceVideoPlaybackReference.episodeKey(
                    vodID: route.vodID,
                    sourceIndex: route.sourceIndex,
                    episodeIndex: route.episodeIndex
                )
            } else {
                routeKey = href
            }

            guard seenRoutes.contains(routeKey) == false else {
                continue
            }

            seenRoutes.insert(routeKey)
            uniqueElements.append(element)
        }

        return uniqueElements
    }

    private func sortedVfedEpisodeElements(_ elements: [Element]) throws -> [Element] {
        let indexedElements: [(offset: Int, element: Element)] = elements.enumerated().map { pair in
            return (offset: pair.offset, element: pair.element)
        }

        return try indexedElements.sorted { lhs, rhs in
            let lhsHref: String = try lhs.element.attr("href")
            let rhsHref: String = try rhs.element.attr("href")
            let lhsRoute: VideoPlayRoute? = self.playRoute(from: URL(string: lhsHref)?.path ?? lhsHref)
            let rhsRoute: VideoPlayRoute? = self.playRoute(from: URL(string: rhsHref)?.path ?? rhsHref)
            switch (lhsRoute?.episodeIndex, rhsRoute?.episodeIndex) {
            case let (lhsIndex?, rhsIndex?) where lhsIndex != rhsIndex:
                return lhsIndex < rhsIndex
            default:
                return lhs.offset < rhs.offset
            }
        }
        .map(\.element)
    }

    private func isElement(_ element: Element, insideOwnVfedPlayItem playItem: Element) -> Bool {
        var parent: Element? = element.parent()
        while let current: Element = parent {
            if current === playItem {
                return true
            }
            if current.hasClass("fed-play-item") {
                return false
            }
            parent = current.parent()
        }

        return true
    }

    private func shouldIncludeEpisodeLink(_ element: Element) throws -> Bool {
        let classes: [String] = try element.attr("class")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        if classes.contains("fed-deta-play") {
            return false
        }

        return true
    }

    private func vfedPlayItemPreferenceScore(_ element: Element) throws -> Int {
        let headerText: String = try self.vfedPlayItemTitle(element)
        let itemText: String = try element.text()
        let text: String = "\(headerText) \(itemText)"
        var score: Int = 100

        if text.range(of: "VIP解析", options: [.caseInsensitive, .widthInsensitive]) != nil {
            score -= 100
        }
        if text.range(of: "第三方提供", options: [.caseInsensitive, .widthInsensitive]) != nil {
            score -= 80
        }
        if text.range(of: "超清AB线", options: [.caseInsensitive, .widthInsensitive]) != nil ||
            text.range(of: "超清EV线", options: [.caseInsensitive, .widthInsensitive]) != nil {
            score -= 80
        }
        return score
    }

    private func vfedPlayItemTitle(_ element: Element) throws -> String {
        return try element.select(".fed-drop-head").text().trimmedNonEmpty ?? "unknown"
    }

    private func normalizedVfedPlayItemTitle(_ title: String) -> String? {
        let normalized: String = title
            .replacingOccurrences(of: "来自", with: "")
            .replacingOccurrences(of: "的播放列表", with: "")
            .replacingOccurrences(of: "视频排序：正序", with: "")
            .replacingOccurrences(of: "视频排序：倒序", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.trimmedNonEmpty
    }

    private func sortedEpisodes(_ episodes: [VideoEpisode]) -> [VideoEpisode] {
        let indexedEpisodes: [(offset: Int, episode: VideoEpisode)] = episodes.enumerated().map { pair in
            return (offset: pair.offset, episode: pair.element)
        }

        return indexedEpisodes.sorted { lhs, rhs in
            let lhsKey: Int? = self.episodeSortKey(lhs.episode)
            let rhsKey: Int? = self.episodeSortKey(rhs.episode)
            switch (lhsKey, rhsKey) {
            case let (lhsKey?, rhsKey?) where lhsKey != rhsKey:
                return lhsKey < rhsKey
            default:
                return lhs.offset < rhs.offset
            }
        }
        .map { item in
            return item.episode
        }
    }

    private func episodeSortKey(_ episode: VideoEpisode) -> Int? {
        let titlePatterns: [String] = [
            #"(?i)EP0*(\d+)"#,
            #"第0*(\d+)[集话話回]"#
        ]

        for pattern: String in titlePatterns {
            if let value: String = self.firstMatch(episode.title, pattern: pattern),
               let number: Int = Int(value) {
                return number
            }
        }

        guard let value: String = self.firstMatch(episode.id, pattern: #"-0*(\d+)$"#) else {
            return nil
        }
        return Int(value)
    }

    func mapPlayback(
        html: String,
        definition: SourceDefinition,
        playPageURL: URL
    ) throws -> SourceVideoPlaybackReference {
        let document: Document = try SwiftSoup.parse(html, playPageURL.absoluteString)
        let payload: PlayerPayload? = self.playerPayload(from: html)
        let route: VideoPlayRoute? = self.playRoute(from: playPageURL.path)
        let vodID: String = payload?.id ?? route?.vodID ?? "unknown"
        let sourceIndex: Int = payload?.sid ?? route?.sourceIndex ?? 1
        let episodeIndex: Int = payload?.nid ?? route?.episodeIndex ?? 1
        let candidate: VideoPlaybackCandidate = try self.playbackCandidate(
            payload: payload,
            document: document,
            baseURL: playPageURL
        )
        let resolution: VideoPlaybackResolution = self.playbackResolution(
            candidate: candidate,
            playPageURL: playPageURL,
            html: html
        )

        return SourceVideoPlaybackReference(
            vodID: vodID,
            sourceIndex: sourceIndex,
            episodeIndex: episodeIndex,
            episodeKey: SourceVideoPlaybackReference.episodeKey(
                vodID: vodID,
                sourceIndex: sourceIndex,
                episodeIndex: episodeIndex
            ),
            episodeTitle: try self.episodeTitle(from: document),
            playPageURL: playPageURL,
            candidateMediaURL: resolution.candidateMediaURL,
            candidateMediaKind: resolution.candidateMediaKind,
            playbackRequestConfig: resolution.playbackRequestConfig,
            nextEpisodeURL: self.absoluteURL(payload?.link_next, baseURL: playPageURL),
            previousEpisodeURL: self.absoluteURL(payload?.link_pre, baseURL: playPageURL),
            sourceName: payload?.from,
            status: resolution.status
        )
    }

    private func detailURL(from element: Element, baseURL: URL) throws -> URL? {
        let href: String? = try element.select(Selectors.detailLinks)
            .first()?
            .attr("href")
            .trimmedNonEmpty

        guard let href: String else {
            return nil
        }

        return URL(string: href, relativeTo: baseURL)?.absoluteURL
    }

    private func title(from element: Element) throws -> String? {
        if let title: String = try element.select(Selectors.titleAttributes)
            .first()?
            .attr("title")
            .trimmedNonEmpty {
            return title
        }

        return try element.select(Selectors.titleTexts)
            .first()?
            .text()
            .trimmedNonEmpty
    }

    private func coverURL(from element: Element, baseURL: URL) throws -> URL? {
        let fallbackValue: String? = try self.onerrorFallbackCoverValue(from: element)
        let elements: [Element] = try element.select(Selectors.covers).array()
        for element: Element in elements {
            let candidates: [String?] = [
                try element.attr("data-original").trimmedNonEmpty,
                try element.attr("data-src").trimmedNonEmpty,
                try element.attr("src").trimmedNonEmpty
            ]

            for candidate: String? in candidates {
                guard let value: String = candidate,
                      self.isUsableCoverValue(value),
                      let url: URL = URL(string: value, relativeTo: baseURL)?.absoluteURL,
                      self.isHTTPImageURL(url) else {
                    continue
                }

                if self.shouldPreferFallbackCoverValue(value),
                   let fallbackValue: String,
                   let fallbackURL: URL = URL(string: fallbackValue, relativeTo: baseURL)?.absoluteURL,
                   self.isHTTPImageURL(fallbackURL) {
                    return fallbackURL
                }

                return url
            }
        }

        return nil
    }

    private func onerrorFallbackCoverValue(from element: Element) throws -> String? {
        let elements: [Element] = try element.select("[onerror]").array()
        for element: Element in elements {
            let script: String = try element.attr("onerror")
            for pattern: String in [
                #"attr\(\s*['"]src['"]\s*,\s*['"]([^'"]+)['"]\s*\)"#,
                #"data\(\s*['"]original['"]\s*,\s*['"]([^'"]+)['"]\s*\)"#
            ] {
                guard let value: String = self.firstMatch(script, pattern: pattern),
                      self.isUsableCoverValue(value) else {
                    continue
                }

                return value
            }
        }

        return nil
    }

    private func shouldPreferFallbackCoverValue(_ value: String) -> Bool {
        guard let url: URL = URL(string: value),
              let host: String = url.host?.lowercased() else {
            return false
        }

        return host.contains("doubanio.com") ||
            host == "m.media-amazon.com" ||
            host == "image.tmdb.org"
    }

    private func isUsableCoverValue(_ value: String) -> Bool {
        let normalized: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased: String = normalized.lowercased()
        return normalized.isEmpty == false &&
            lowercased != "arraycover" &&
            lowercased != "null" &&
            lowercased != "undefined" &&
            lowercased.hasPrefix("data:") == false &&
            lowercased.hasPrefix("javascript:") == false &&
            lowercased.hasPrefix("about:") == false
    }

    private func isHTTPImageURL(_ url: URL) -> Bool {
        let scheme: String = url.scheme?.lowercased() ?? ""
        return scheme == "http" || scheme == "https"
    }

    private func latestText(from element: Element) throws -> String? {
        return try element.select(Selectors.latestTexts)
            .first()?
            .text()
            .trimmedNonEmpty
    }

    private func synopsis(from document: Document) throws -> String? {
        let selectors: [String] = [
            ".ewave-content__detail .desc",
            ".ewave-content__desc",
            ".detail-content",
            ".vod_content",
            ".content",
            ".ewave-content__detail p"
        ]
        var candidates: [String] = []

        for selector: String in selectors {
            let elements: [Element] = try document.select(selector).array()
            for element: Element in elements {
                guard let text: String = try element.text().cleanedDetailText,
                      candidates.contains(text) == false else {
                    continue
                }

                candidates.append(text)
            }
        }

        for selector: String in ["meta[name=description][content]", "meta[property=og:description][content]"] {
            guard let text: String = self.firstAttribute(in: document, selector: selector, attribute: "content")?.cleanedDetailText,
                  candidates.contains(text) == false else {
                continue
            }

            candidates.append(text)
        }

        if let explicitSynopsis: String = candidates.first(where: { text in
            return text.contains("简介") || text.contains("剧情")
        }) {
            return self.strippedSynopsisPrefix(explicitSynopsis)
        }

        return candidates
            .filter { text in
                return text.count >= 30 && self.looksLikeMetadata(text) == false
            }
            .max { lhs, rhs in
                return lhs.count < rhs.count
            }
    }

    private func strippedSynopsisPrefix(_ text: String) -> String {
        var result: String = text
        let prefixes: [String] = ["剧情简介：", "剧情简介:", "简介：", "简介:", "剧情：", "剧情:"]

        for prefix: String in prefixes where result.hasPrefix(prefix) {
            result.removeFirst(prefix.count)
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }

    private func looksLikeMetadata(_ text: String) -> Bool {
        let metadataKeys: [String] = ["主演", "导演", "类型", "地区", "年份", "语言", "状态", "更新", "别名"]
        return metadataKeys.contains { key in
            return text.hasPrefix(key) || text.hasPrefix("\(key)：") || text.hasPrefix("\(key):")
        }
    }

    private func metadataRows(from document: Document) throws -> [String] {
        let elements: [Element] = try document.select(".ewave-content__detail p, .ewave-content__detail li, .ewave-content__detail span").array()
        var rows: [String] = []

        for element: Element in elements {
            guard let text: String = try element.text().cleanedDetailText,
                  text.count <= 120,
                  text.contains("简介") == false,
                  rows.contains(text) == false else {
                continue
            }

            rows.append(text)
        }

        self.appendMetadataRow(
            "主演",
            value: self.firstAttribute(in: document, selector: "meta[property=og:video:actor][content], meta[itemprop=actor][content]", attribute: "content"),
            to: &rows
        )
        self.appendMetadataRow(
            "类型",
            value: self.firstAttribute(in: document, selector: "meta[property=og:video:class][content], meta[itemprop=class][content]", attribute: "content"),
            to: &rows
        )
        self.appendMetadataRow(
            "地区",
            value: self.firstAttribute(in: document, selector: "meta[property=og:video:area][content], meta[itemprop=contentLocation][content]", attribute: "content"),
            to: &rows
        )
        self.appendMetadataRow(
            "日期",
            value: self.firstAttribute(in: document, selector: "meta[property=og:video:date][content], meta[itemprop=uploadDate][content]", attribute: "content"),
            to: &rows
        )

        return Array(rows.prefix(Defaults.maxMetadataRows))
    }

    private func appendMetadataRow(_ title: String, value: String?, to rows: inout [String]) {
        guard let value: String = value?.cleanedDetailText else {
            return
        }

        let row: String = "\(title)：\(value)"
        guard rows.contains(row) == false else {
            return
        }

        rows.append(row)
    }

    private func vodID(from detailURL: URL) -> String? {
        return self.firstMatch(detailURL.path, pattern: #"^/voddetail/(\d+)(?:\.html|/)?$"#)
    }

    private func playRoute(from path: String) -> VideoPlayRoute? {
        guard let result: NSTextCheckingResult = self.match(
            path,
            pattern: #"^/vodplay/(\d+)-(\d+)-(\d+)(?:\.html|/)?$"#
        ) else {
            return nil
        }

        guard let vodID: String = self.substring(path, range: result.range(at: 1)),
              let sourceIndexText: String = self.substring(path, range: result.range(at: 2)),
              let episodeIndexText: String = self.substring(path, range: result.range(at: 3)),
              let sourceIndex: Int = Int(sourceIndexText),
              let episodeIndex: Int = Int(episodeIndexText) else {
            return nil
        }

        return VideoPlayRoute(
            vodID: vodID,
            sourceIndex: sourceIndex,
            episodeIndex: episodeIndex
        )
    }

    private func playerPayload(from html: String) -> PlayerPayload? {
        guard let json: String = self.firstMatch(
            html,
            pattern: #"var\s+player_aaaa\s*=\s*(\{.*?\})\s*;?\s*</script>"#
        ) else {
            return nil
        }

        return try? JSONDecoder().decode(PlayerPayload.self, from: Data(json.utf8))
    }

    private func playbackCandidate(
        payload: PlayerPayload?,
        document: Document,
        baseURL: URL
    ) throws -> VideoPlaybackCandidate {
        if let mediaURL: URL = self.absoluteURL(payload?.url, baseURL: baseURL) {
            return VideoPlaybackCandidate(
                url: mediaURL,
                kind: self.mediaKind(for: mediaURL)
            )
        }

        if let iframeURL: URL = try self.vfedIframePlayerURL(from: document, baseURL: baseURL) {
            return VideoPlaybackCandidate(url: iframeURL, kind: .iframePlayer)
        }

        return VideoPlaybackCandidate(url: nil, kind: .unknown)
    }

    private func vfedIframePlayerURL(from document: Document, baseURL: URL) throws -> URL? {
        let selectors: [String] = [
            "iframe.fed-play-iframe",
            "#fed-play-iframe",
            ".fed-play-player iframe"
        ]

        for selector: String in selectors {
            let frames: [Element] = try document.select(selector).array()
            for frame: Element in frames {
                let candidates: [String?] = [
                    self.decodedVfedPlayerURL(from: try frame.attr("data-play")),
                    try frame.attr("src").trimmedNonEmpty,
                    try frame.attr("data-src").trimmedNonEmpty
                ]

                for candidate: String? in candidates {
                    guard let candidate: String,
                          let url: URL = URL(string: candidate, relativeTo: baseURL)?.absoluteURL else {
                        continue
                    }

                    return url
                }
            }
        }

        return nil
    }

    private func decodedVfedPlayerURL(from encoded: String) -> String? {
        guard let encoded: String = encoded.trimmedNonEmpty else {
            return nil
        }

        let payload: String = String(encoded.dropFirst(3))
        guard payload.isEmpty == false,
              let data: Data = Data(base64Encoded: payload),
              let decoded: String = String(data: data, encoding: .utf8)?.trimmedNonEmpty else {
            return nil
        }

        return decoded
    }

    private func episodeTitle(from document: Document) throws -> String? {
        return try document.select(Selectors.playerTitles)
            .first()?
            .text()
            .trimmedNonEmpty
    }

    private func absoluteURL(_ string: String?, baseURL: URL) -> URL? {
        guard let string: String = string?.trimmedNonEmpty else {
            return nil
        }

        return URL(string: string, relativeTo: baseURL)?.absoluteURL
    }

    private func mediaKind(for url: URL?) -> SourceVideoMediaKind {
        guard let path: String = url?.path.lowercased() else {
            return .unknown
        }

        if path.hasSuffix(".m3u8") {
            return .m3u8
        }

        if path.hasSuffix(".mp4") {
            return .mp4
        }

        let host: String = url?.host?.lowercased() ?? ""
        if path.contains("embed")
            || path.contains("player")
            || host.contains("iframe")
            || host.hasPrefix("player.") {
            return .iframePlayer
        }

        return .unknown
    }

    private func playbackResolution(
        candidate: VideoPlaybackCandidate,
        playPageURL: URL,
        html: String
    ) -> VideoPlaybackResolution {
        if let resolution: VideoPlaybackResolution = IframePlayerCandidateResolver().resolve(
            candidate: candidate,
            playPageURL: playPageURL,
            html: html
        ) {
            return resolution
        }

        return VideoPlaybackResolution(
            candidateMediaURL: candidate.url,
            candidateMediaKind: candidate.kind,
            playbackRequestConfig: SourcePlaybackRequestConfig(
                headers: BrowserRequestHeaders.Chrome.playbackHeaders(referer: playPageURL),
                referer: playPageURL,
                userAgent: BrowserRequestHeaders.Chrome.chromeUserAgent
            ),
            status: self.playbackStatus(
                mediaURL: candidate.url,
                mediaKind: candidate.kind,
                html: html
            )
        )
    }

    private func playbackStatus(
        mediaURL: URL?,
        mediaKind: SourceVideoMediaKind,
        html: String
    ) -> SourceVideoPlaybackStatus {
        if VideoPlaybackAdMediaFilter.isBlocked(mediaURL) {
            return .failed(.mediaURLNotFound)
        }

        if mediaURL != nil, mediaKind == .m3u8 || mediaKind == .mp4 {
            return .playable
        }

        if mediaURL != nil, mediaKind == .iframePlayer {
            return .pageOnly
        }

        if self.lexicon.containsMarker(in: html, category: .accountRestriction) {
            return .restricted(.requiresLogin)
        }

        if self.lexicon.containsMarker(in: html, category: .payRestriction) {
            return .restricted(.vipOnly)
        }

        if self.lexicon.containsMarker(in: html, category: .macCMSPayload) && mediaURL == nil {
            return .failed(.mediaURLNotFound)
        }

        return .pageOnly
    }

    private func firstMatch(_ string: String, pattern: String) -> String? {
        guard let result: NSTextCheckingResult = self.match(string, pattern: pattern) else {
            return nil
        }

        return self.substring(string, range: result.range(at: 1))
    }

    private func match(_ string: String, pattern: String) -> NSTextCheckingResult? {
        guard let regex: NSRegularExpression = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range: NSRange = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.firstMatch(in: string, range: range)
    }

    private func substring(_ string: String, range: NSRange) -> String? {
        guard range.location != NSNotFound,
              let swiftRange: Range<String.Index> = Range(range, in: string) else {
            return nil
        }

        return String(string[swiftRange])
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
}

private struct VideoPlayRoute {
    var vodID: String
    var sourceIndex: Int
    var episodeIndex: Int
}

private struct VfedEpisodeEntry {
    var element: Element
    var lineTitle: String?
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var cleanedDetailText: String? {
        let collapsed: String = self
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .split(whereSeparator: { character in
                return character.isWhitespace
            })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return collapsed.isEmpty ? nil : collapsed
    }
}
