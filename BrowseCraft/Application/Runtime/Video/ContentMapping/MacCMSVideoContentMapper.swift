import Foundation
import SwiftSoup
import BrowseCraftCore

// 中文注释：MacCMSVideoContentMapper 只处理 MacCMS 常见 HTML/DOM，不处理 VIP/DRM/反爬绕过。
struct MacCMSVideoContentMapper: VideoContentMapper {
    private static let playbackUserAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

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
            ".module-card-item"
        ].joined(separator: ", ")

        static let detailLinks: String = [
            "a.thumb-link[href^=\"/voddetail/\"]",
            "h4 a[href^=\"/voddetail/\"]",
            ".module-item-pic[href^=\"/voddetail/\"]",
            ".module-card-item-title[href^=\"/voddetail/\"]",
            "a[href*=\"/voddetail/\"]"
        ].joined(separator: ", ")

        static let titleAttributes: String = [
            ".ewave-vodlist__thumb[title]",
            ".stui-vodlist__thumb[title]",
            ".myui-vodlist__thumb[title]",
            ".module-item-pic[title]"
        ].joined(separator: ", ")

        static let titleTexts: String = [
            ".ewave-vodlist__detail h4 a",
            ".stui-vodlist__detail h4 a",
            ".myui-vodlist__detail h4 a",
            ".module-card-item-title",
            "h4.title a"
        ].joined(separator: ", ")

        static let covers: String = [
            ".ewave-vodlist__thumb[data-original]",
            ".stui-vodlist__thumb[data-original]",
            ".myui-vodlist__thumb[data-original]",
            ".module-item-pic[data-src]",
            "img[data-original]",
            "img[data-src]",
            "img[src]"
        ].joined(separator: ", ")

        static let latestTexts: String = [
            ".pic-text.text-right",
            ".pic-text",
            ".module-item-note",
            ".module-item-text"
        ].joined(separator: ", ")

        static let episodeLinks: String = [
            ".ewave-content__playlist a[href^=\"/vodplay/\"]",
            ".ewave-content__playlist a[href*=\"/vodplay/\"]",
            ".stui-content__playlist a[href^=\"/vodplay/\"]",
            ".stui-content__playlist a[href*=\"/vodplay/\"]",
            ".myui-content__list a[href^=\"/vodplay/\"]",
            ".myui-content__list a[href*=\"/vodplay/\"]",
            ".module-play-list a[href^=\"/vodplay/\"]",
            ".module-play-list a[href*=\"/vodplay/\"]"
        ].joined(separator: ", ")

        static let playerTitles: String = [
            ".ewave-player__detail h1.title a",
            ".stui-player__detail h1.title a",
            ".myui-player__detail h1.title a",
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

    func mapDetail(
        html: String,
        definition: SourceDefinition,
        detailURL: URL
    ) throws -> VideoDetailContent {
        let document: Document = try SwiftSoup.parse(html, detailURL.absoluteString)
        let elements: [Element] = try document.select(Selectors.episodeLinks).array()
        var episodes: [VideoEpisode] = []

        for element: Element in elements {
            guard let href: String = try element.attr("href").trimmedNonEmpty,
                  let url: URL = URL(string: href, relativeTo: detailURL)?.absoluteURL,
                  let route: VideoPlayRoute = self.playRoute(from: url.path) else {
                continue
            }

            let title: String = try element.text().trimmedNonEmpty ?? "Episode \(route.episodeIndex)"
            episodes.append(
                VideoEpisode(
                    id: SourceVideoPlaybackReference.episodeKey(
                        vodID: route.vodID,
                        sourceIndex: route.sourceIndex,
                        episodeIndex: route.episodeIndex
                    ),
                    title: title,
                    playPageURL: url
                )
            )
        }

        return VideoDetailContent(
            episodes: episodes,
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
        let payload: PlayerPayload? = self.playerPayload(from: html)
        let route: VideoPlayRoute? = self.playRoute(from: playPageURL.path)
        let vodID: String = payload?.id ?? route?.vodID ?? "unknown"
        let sourceIndex: Int = payload?.sid ?? route?.sourceIndex ?? 1
        let episodeIndex: Int = payload?.nid ?? route?.episodeIndex ?? 1
        let mediaURL: URL? = self.absoluteURL(payload?.url, baseURL: playPageURL)
        let mediaKind: SourceVideoMediaKind = self.mediaKind(for: mediaURL)
        let resolution: VideoPlaybackResolution = self.playbackResolution(
            candidate: VideoPlaybackCandidate(
                url: mediaURL,
                kind: mediaKind
            ),
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
        let value: String? = try element.select(Selectors.covers)
            .first()
            .flatMap { element in
                return try? element.attr("data-original").trimmedNonEmpty
                    ?? element.attr("data-src").trimmedNonEmpty
                    ?? element.attr("src").trimmedNonEmpty
            }

        guard let value: String else {
            return nil
        }

        return URL(string: value, relativeTo: baseURL)?.absoluteURL
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

        return Array(rows.prefix(Defaults.maxMetadataRows))
    }

    private func vodID(from detailURL: URL) -> String? {
        return self.firstMatch(detailURL.path, pattern: #"^/voddetail/(\d+)\.html$"#)
    }

    private func playRoute(from path: String) -> VideoPlayRoute? {
        guard let result: NSTextCheckingResult = self.match(
            path,
            pattern: #"^/vodplay/(\d+)-(\d+)-(\d+)\.html$"#
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
                headers: [
                    "Referer": playPageURL.absoluteString,
                    "User-Agent": Self.playbackUserAgent
                ],
                referer: playPageURL,
                userAgent: Self.playbackUserAgent
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
        if mediaURL != nil, mediaKind == .m3u8 || mediaKind == .mp4 {
            return .playable
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
}

private struct VideoPlayRoute {
    var vodID: String
    var sourceIndex: Int
    var episodeIndex: Int
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
