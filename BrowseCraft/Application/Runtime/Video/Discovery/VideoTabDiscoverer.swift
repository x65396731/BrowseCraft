import Foundation
import SwiftSoup
import BrowseCraftCore

// 中文注释：VideoTabDiscovering 只负责从入口页发现视频列表 tab，不负责解析列表、详情或播放。
protocol VideoTabDiscovering {
    func discoverTabs(
        html: String,
        definition: VideoSourceDefinition,
        pageURL: URL
    ) throws -> [VideoSourceListTab]
}

enum VideoTabDiscoveryDefaults {
    static func homeTab(
        for definition: VideoSourceDefinition,
        itemSelector: String? = nil,
        titleSelector: String? = nil,
        linkSelector: String? = nil,
        coverSelector: String? = nil,
        latestTextSelector: String? = nil
    ) -> VideoSourceListTab {
        return VideoSourceListTab(
            id: "video.home",
            title: "首页",
            url: definition.entryURL.absoluteString,
            itemSelector: itemSelector,
            titleSelector: titleSelector,
            linkSelector: linkSelector,
            coverSelector: coverSelector,
            latestTextSelector: latestTextSelector
        )
    }
}

struct FallbackVideoTabDiscoverer: VideoTabDiscovering {
    func discoverTabs(
        html: String,
        definition: VideoSourceDefinition,
        pageURL: URL
    ) throws -> [VideoSourceListTab] {
        _ = html
        _ = pageURL

        return [
            VideoTabDiscoveryDefaults.homeTab(for: definition)
        ]
    }
}

struct VideoTabDiscoveryLink: Hashable {
    var title: String
    var url: URL
}

enum VideoTabDiscoveryUtilities {
    static func links(
        from document: Document,
        baseURL: URL,
        selectors: [String]
    ) throws -> [VideoTabDiscoveryLink] {
        var links: [VideoTabDiscoveryLink] = []

        for selector: String in selectors {
            let elements: [Element] = try document.select(selector).array()
            links.append(contentsOf: try self.links(from: elements, baseURL: baseURL))
        }

        return links
    }

    static func links(
        from elements: [Element],
        baseURL: URL
    ) throws -> [VideoTabDiscoveryLink] {
        var links: [VideoTabDiscoveryLink] = []

        for element: Element in elements {
            guard let href: String = try element.attr("href").trimmedNonEmpty,
                  let url: URL = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  let title: String = try self.title(from: element) else {
                continue
            }

            links.append(
                VideoTabDiscoveryLink(
                    title: title,
                    url: url
                )
            )
        }

        return links
    }

    static func deduplicated(_ links: [VideoTabDiscoveryLink]) -> [VideoTabDiscoveryLink] {
        var seenKeys: Set<String> = Set<String>()
        var result: [VideoTabDiscoveryLink] = []

        for link: VideoTabDiscoveryLink in links {
            let key: String = self.normalizedURLKey(link.url)
            guard seenKeys.contains(key) == false else {
                continue
            }

            seenKeys.insert(key)
            result.append(link)
        }

        return result
    }

    static func stableTabID(prefix: String, url: URL) -> String {
        let raw: String = [
            url.host ?? "",
            url.path,
            url.query ?? ""
        ]
        .joined(separator: "-")

        let allowed: CharacterSet = CharacterSet.alphanumerics
        let slug: String = raw.unicodeScalars
            .map { scalar in
                allowed.contains(scalar) ? String(scalar).lowercased() : "-"
            }
            .joined()
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return "\(prefix).\(slug.isEmpty ? "tab" : slug)"
    }

    static func normalizedURLKey(_ url: URL) -> String {
        var components: URLComponents? = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }

    private static func title(from element: Element) throws -> String? {
        let text: String? = try element.text().trimmedNonEmpty
        let title: String? = try element.attr("title").trimmedNonEmpty
        let ariaLabel: String? = try element.attr("aria-label").trimmedNonEmpty

        return text ?? title ?? ariaLabel
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed: String = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
