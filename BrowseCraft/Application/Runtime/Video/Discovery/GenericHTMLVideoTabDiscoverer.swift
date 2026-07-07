import Foundation
import SwiftSoup
import BrowseCraftCore

struct GenericHTMLVideoTabDiscoverer: VideoTabDiscovering {
    private enum Defaults {
        // Generic HTML tabs are guessed from broad navigation areas; cap auto-discovery to avoid importing noisy site links.
        static let maxAutoDiscoveredTabs: Int = 12
    }

    private enum Selectors {
        static let candidateLinks: [String] = [
            "nav a[href]",
            "header a[href]",
            ".navbar a[href]",
            ".nav a[href]",
            ".menu a[href]",
            ".main-menu a[href]",
            ".sub-menu a[href]",
            ".categories a[href]",
            ".category a[href]",
            ".cat a[href]",
            "[class*=\"categor\"] a[href]",
            "[class*=\"menu\"] a[href]",
            "[class*=\"nav\"] a[href]"
        ]

        static let itemSelector: String = ".frame-block.thumb-block, article, .video-item, .video-card, .movie, .vod, .list-item"
        static let titleSelector: String = ".thumb-under .title a@title, a@title, img@alt"
        static let linkSelector: String = ".thumb a[href]@href, .thumb-under .title a[href]@href, a[href*=video]@href, a[href*=watch]@href, a[href*=play]@href"
        static let coverSelector: String = "img[data-original], img[data-src], img[data-thumb], img[src]"
        static let latestTextSelector: String = ".duration, .latest, .episode, .remarks, .tag, .meta, .metadata"
    }

    private let maxDiscoveredTabs: Int
    private let lexicon: VideoDetectionLexicon

    init(
        maxDiscoveredTabs: Int = Defaults.maxAutoDiscoveredTabs,
        lexicon: VideoDetectionLexicon = .default
    ) {
        self.maxDiscoveredTabs = maxDiscoveredTabs
        self.lexicon = lexicon
    }

    func discoverTabs(
        html: String,
        definition: VideoSourceDefinition,
        pageURL: URL
    ) throws -> [VideoSourceListTab] {
        let document: Document = try SwiftSoup.parse(html, pageURL.absoluteString)
        let candidates: [VideoTabDiscoveryLink] = try VideoTabDiscoveryUtilities.deduplicated(
            VideoTabDiscoveryUtilities.links(
                from: document,
                baseURL: pageURL,
                selectors: Selectors.candidateLinks
            )
            .filter { link in
                self.isDiscoverableLink(link, definition: definition)
            }
        )

        return self.tabs(
            from: Array(candidates.prefix(self.maxDiscoveredTabs)),
            definition: definition
        )
    }

    private func tabs(
        from links: [VideoTabDiscoveryLink],
        definition: VideoSourceDefinition
    ) -> [VideoSourceListTab] {
        var tabs: [VideoSourceListTab] = [
            self.homeTab(for: definition)
        ]

        for link: VideoTabDiscoveryLink in links {
            let title: String = self.normalizedTitle(link.title)
            guard title.isEmpty == false,
                  self.isHomeURL(link.url, definition: definition) == false else {
                continue
            }

            tabs.append(
                VideoSourceListTab(
                    id: VideoTabDiscoveryUtilities.stableTabID(prefix: "video.category", url: link.url),
                    title: title,
                    url: link.url.absoluteString,
                    itemSelector: Selectors.itemSelector,
                    titleSelector: Selectors.titleSelector,
                    linkSelector: Selectors.linkSelector,
                    coverSelector: Selectors.coverSelector,
                    latestTextSelector: Selectors.latestTextSelector
                )
            )
        }

        return tabs
    }

    private func homeTab(for definition: VideoSourceDefinition) -> VideoSourceListTab {
        return VideoTabDiscoveryDefaults.homeTab(
            for: definition,
            itemSelector: Selectors.itemSelector,
            titleSelector: Selectors.titleSelector,
            linkSelector: Selectors.linkSelector,
            coverSelector: Selectors.coverSelector,
            latestTextSelector: Selectors.latestTextSelector
        )
    }

    private func isDiscoverableLink(
        _ link: VideoTabDiscoveryLink,
        definition: VideoSourceDefinition
    ) -> Bool {
        guard self.isSameSite(link.url, entryURL: definition.entryURL),
              self.isHomeURL(link.url, definition: definition) == false,
              self.isRejected(link) == false else {
            return false
        }

        let path: String = link.url.path.lowercased()
        let query: String = link.url.query?.lowercased() ?? ""

        return path == "/"
            || path.contains("/c/")
            || path.contains("/category")
            || path.contains("/categories")
            || path.contains("/tag")
            || path.contains("/tags")
            || path.contains("/channel")
            || path.contains("/channels")
            || path.contains("/new")
            || path.contains("/best")
            || path.contains("/popular")
            || path.contains("/top")
            || path.contains("/search")
            || query.contains("k=")
            || query.contains("category=")
    }

    private func isSameSite(_ url: URL, entryURL: URL) -> Bool {
        guard let host: String = url.host?.lowercased(),
              let entryHost: String = entryURL.host?.lowercased() else {
            return false
        }

        return host == entryHost
    }

    private func isHomeURL(_ url: URL, definition: VideoSourceDefinition) -> Bool {
        return VideoTabDiscoveryUtilities.normalizedURLKey(url)
            == VideoTabDiscoveryUtilities.normalizedURLKey(definition.entryURL)
    }

    private func isRejected(_ link: VideoTabDiscoveryLink) -> Bool {
        let text: String = [
            link.title,
            link.url.path,
            link.url.query ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        return self.lexicon.containsMarker(in: text, category: .navigationReject)
    }

    private func normalizedTitle(_ title: String) -> String {
        return title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
