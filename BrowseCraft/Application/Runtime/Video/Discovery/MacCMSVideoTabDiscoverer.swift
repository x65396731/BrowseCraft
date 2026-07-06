import Foundation
import SwiftSoup
import BrowseCraftCore

struct MacCMSVideoTabDiscoverer: VideoTabDiscovering {
    private enum Selectors {
        static let categoryLinks: [String] = [
            "nav a[href]",
            "header a[href]",
            ".navbar a[href]",
            ".nav a[href]",
            ".menu a[href]",
            ".menu-box a[href]",
            ".stui-header__menu a[href]",
            ".myui-header__menu a[href]",
            ".ewave-header__menu a[href]",
            "a[href*=\"/vodtype/\"]",
            "a[href*=\"/vodshow/\"]"
        ]

        static let itemSelector: String = ".ewave-vodlist__box, .stui-vodlist__box, .myui-vodlist__box, .module-item, .module-card-item"
        static let titleSelector: String = ".ewave-vodlist__thumb@title, .stui-vodlist__thumb@title, .myui-vodlist__thumb@title, .module-item-pic@title"
        static let linkSelector: String = "a[href*=/voddetail/]@href"
        static let coverSelector: String = ".ewave-vodlist__thumb@data-original, .stui-vodlist__thumb@data-original, .myui-vodlist__thumb@data-original, img[data-original], img[data-src], img[src]"
        static let latestTextSelector: String = ".pic-text.text-right, .pic-text, .module-item-note, .module-item-text"
    }

    func discoverTabs(
        html: String,
        definition: VideoSourceDefinition,
        pageURL: URL
    ) throws -> [VideoSourceListTab] {
        let document: Document = try SwiftSoup.parse(html, pageURL.absoluteString)
        let links: [VideoTabDiscoveryLink] = try VideoTabDiscoveryUtilities.deduplicated(
            VideoTabDiscoveryUtilities.links(
                from: document,
                baseURL: pageURL,
                selectors: Selectors.categoryLinks
            )
            .filter { link in
                self.isCategoryLink(link.url)
            }
        )

        return self.tabs(
            from: links,
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

    private func isCategoryLink(_ url: URL) -> Bool {
        let path: String = url.path.lowercased()
        return path.contains("/vodtype/")
            || path.contains("/vodshow/")
    }

    private func isHomeURL(_ url: URL, definition: VideoSourceDefinition) -> Bool {
        return VideoTabDiscoveryUtilities.normalizedURLKey(url)
            == VideoTabDiscoveryUtilities.normalizedURLKey(definition.entryURL)
    }

    private func normalizedTitle(_ title: String) -> String {
        return title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
