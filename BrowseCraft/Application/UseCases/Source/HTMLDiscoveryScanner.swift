import Foundation
import SwiftSoup

typealias HTMLDiscoveryElement = Element

// 中文注释：HTMLDiscoveryScanner 只提供中立 HTML 扫描工具，不承载漫画或影视业务判定。
struct HTMLDiscoveryScanner {
    private let urlResolver: URLResolvingService

    init(urlResolver: URLResolvingService = URLResolvingService()) {
        self.urlResolver = urlResolver
    }

    func siteURL(from rawValue: String) throws -> URL {
        let trimmed: String = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            normalized = trimmed
        } else {
            normalized = "https://\(trimmed)"
        }

        guard let url: URL = URL(string: normalized),
              let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw URLResolvingError.invalidURL(rawValue)
        }

        return url
    }

    func candidateSearchURLs(
        siteURL: URL,
        keyword: String,
        preferredPathBuilders: [(String) -> [String]],
        additionalRawCandidates: [String]
    ) -> [URL] {
        var urls: [URL] = []
        guard keyword.isEmpty == false,
              let encodedKeyword: String = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return [siteURL]
        }

        let baseURLString: String = siteURL.absoluteString
        let root: String = "\(siteURL.scheme ?? "https")://\(siteURL.host ?? "")"
        let sitePath: String = siteURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var preferredCandidates: [String] = preferredPathBuilders.flatMap { builder in
            builder(encodedKeyword)
        }
        if sitePath.isEmpty == false {
            let scopedPath: String = "/\(sitePath)"
            preferredCandidates.append("\(scopedPath)/search?keyword=\(encodedKeyword)")
            preferredCandidates.append("\(scopedPath)/search?q=\(encodedKeyword)")
        }

        let rawCandidates: [String] = preferredCandidates + [
            "/search?keyword=\(encodedKeyword)",
            "/search?q=\(encodedKeyword)",
            "/search?wd=\(encodedKeyword)",
            "/?s=\(encodedKeyword)",
            "/search/\(encodedKeyword)",
            "/so/\(encodedKeyword)"
        ] + additionalRawCandidates + [
            siteURL.path.isEmpty || siteURL.path == "/" ? "/" : siteURL.path
        ]

        for rawCandidate: String in rawCandidates {
            let absoluteString: String = self.urlResolver.absoluteString(rawCandidate, baseURLString: root)
            if let url: URL = URL(string: absoluteString),
               urls.contains(url) == false {
                urls.append(url)
            }
        }

        if let url: URL = URL(string: baseURLString), urls.contains(url) == false {
            urls.append(url)
        }

        return urls
    }

    func anchors(html: String, pageURL: URL) throws -> [HTMLDiscoveryElement] {
        let document: Document = try SwiftSoup.parse(html, pageURL.absoluteString)
        return try document.select("a[href]").array()
    }

    func bestTitle(anchor: HTMLDiscoveryElement, fallback: String) -> String {
        if fallback.isEmpty == false {
            return fallback
        }

        let titleAttribute: String = (try? anchor.attr("title")) ?? ""
        let title: String = self.normalizedText(titleAttribute)
        if title.isEmpty == false {
            return title
        }

        if let images: Elements = try? anchor.select("img"),
           let image: Element = images.first(),
           let imageAlt: String = try? image.attr("alt") {
            return self.normalizedText(imageAlt)
        }

        return ""
    }

    func coverSearchContainers(startingAt anchor: HTMLDiscoveryElement, ancestorLimit: Int = 12) -> [HTMLDiscoveryElement] {
        var containers: [HTMLDiscoveryElement] = [anchor]
        var current: HTMLDiscoveryElement? = anchor
        for _ in 0..<ancestorLimit {
            guard let parent: HTMLDiscoveryElement = current?.parent() else {
                break
            }

            containers.append(parent)
            current = parent
        }

        return containers
    }

    func coverURLString(from container: HTMLDiscoveryElement) throws -> String? {
        let selector: String = [
            "img[data-original]",
            "img[data-src]",
            "img[data-lazy-src]",
            "img[data-srcset]",
            "img[srcset]",
            "img[src]",
            "source[data-srcset]",
            "source[srcset]",
            "picture source[data-srcset]",
            "picture source[srcset]",
            "[style*=\"background-image\"]",
            "[style*=\"url(\"]"
        ].joined(separator: ",")
        let elements: [HTMLDiscoveryElement]
        if try container.select(selector).isEmpty() == false {
            elements = try container.select(selector).array()
        } else {
            elements = [container]
        }

        for element: HTMLDiscoveryElement in elements {
            if let value: String = try self.directCoverURLString(from: element) {
                return value
            }
        }

        return nil
    }

    func normalizedText(_ text: String) -> String {
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { part in part.isEmpty == false }
            .joined(separator: " ")
    }

    func isUsableCoverURLString(_ value: String) -> Bool {
        return value.isEmpty == false
            && value.hasPrefix("data:") == false
            && value.hasPrefix("blob:") == false
            && value != "#"
    }

    func isBlockedCoverURLString(_ value: String) -> Bool {
        let lowercasedValue: String = value.lowercased()
        return lowercasedValue.hasSuffix(".svg")
            || lowercasedValue.contains("/logo")
            || lowercasedValue.contains("logo-")
    }

    private func directCoverURLString(from element: HTMLDiscoveryElement) throws -> String? {
        let directAttributes: [String] = [
            "data-original",
            "data-src",
            "data-lazy-src",
            "data-thumb",
            "data-image",
            "data-img",
            "data-poster",
            "poster",
            "content",
            "src"
        ]
        for attributeName: String in directAttributes {
            let value: String = try element.attr(attributeName).trimmingCharacters(in: .whitespacesAndNewlines)
            if self.isUsableCoverURLString(value) {
                return value
            }
        }

        if let value: String = self.firstSrcsetURL(try element.attr("data-srcset")) {
            return value
        }

        if let value: String = self.firstSrcsetURL(try element.attr("srcset")) {
            return value
        }

        return self.firstStyleURL(try element.attr("style"))
    }

    private func firstSrcsetURL(_ srcset: String) -> String? {
        return srcset
            .split(separator: ",")
            .lazy
            .compactMap { candidate -> String? in
                let value: String? = candidate
                    .split(whereSeparator: { character in
                        return character.isWhitespace
                    })
                    .first
                    .map(String.init)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard let value: String, self.isUsableCoverURLString(value) else {
                    return nil
                }

                return value
            }
            .first
    }

    private func firstStyleURL(_ style: String) -> String? {
        guard let regex: NSRegularExpression = try? NSRegularExpression(
            pattern: #"url\((?:'|")?([^)'"]+)(?:'|")?\)"#
        ) else {
            return nil
        }

        let range: NSRange = NSRange(style.startIndex..<style.endIndex, in: style)
        guard let match: NSTextCheckingResult = regex.firstMatch(in: style, range: range),
              match.numberOfRanges > 1,
              let matchRange: Range<String.Index> = Range(match.range(at: 1), in: style) else {
            return nil
        }

        let value: String = String(style[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return self.isUsableCoverURLString(value) ? value : nil
    }
}
