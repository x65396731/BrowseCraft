import Foundation
import SwiftSoup

/// 中文注释：SwiftSoup 只在此 adapter 内执行 Discovery 所需的有限 DOM 查询并输出值快照。
struct SwiftSoupHTMLDiscoveryParser: HTMLDiscoveryParsingService {
    private static let ancestorLimit: Int = 12

    func parseAnchors(html: String, pageURL: URL) throws -> [HTMLDiscoveryAnchorSnapshot] {
        let document: Document = try SwiftSoup.parse(html, pageURL.absoluteString)
        return try document.select("a[href]").array().map { anchor in
            try self.snapshot(for: anchor)
        }
    }

    private func snapshot(for anchor: Element) throws -> HTMLDiscoveryAnchorSnapshot {
        let image: Element? = (try? anchor.select("img"))?.first()
        var ancestorElements: [Element] = []
        var current: Element? = anchor
        for _ in 0..<Self.ancestorLimit {
            guard let parent: Element = current?.parent() else {
                break
            }
            ancestorElements.append(parent)
            current = parent
        }

        let containers: [Element] = [anchor] + ancestorElements
        let coverURLCandidates: [String] = try containers.compactMap { container in
            try self.coverURLString(from: container)
        }

        return HTMLDiscoveryAnchorSnapshot(
            text: try anchor.text(),
            href: try anchor.attr("href"),
            title: (try? anchor.attr("title")) ?? "",
            imageAlt: image.flatMap { try? $0.attr("alt") } ?? "",
            className: (try? anchor.className()) ?? "",
            id: (try? anchor.attr("id")) ?? "",
            hasImage: image != nil,
            ancestors: ancestorElements.map { element in
                HTMLDiscoveryAncestorSnapshot(
                    text: (try? element.text()) ?? "",
                    className: (try? element.className()) ?? "",
                    id: (try? element.attr("id")) ?? ""
                )
            },
            coverURLCandidates: coverURLCandidates
        )
    }

    private func coverURLString(from container: Element) throws -> String? {
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
        let selected: Elements = try container.select(selector)
        let elements: [Element] = selected.isEmpty() ? [container] : selected.array()

        for element: Element in elements {
            if let value: String = try self.directCoverURLString(from: element) {
                return value
            }
        }
        return nil
    }

    private func directCoverURLString(from element: Element) throws -> String? {
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
            let value: String = try element.attr(attributeName)
                .trimmingCharacters(in: .whitespacesAndNewlines)
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
                    .split(whereSeparator: { $0.isWhitespace })
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

    private func isUsableCoverURLString(_ value: String) -> Bool {
        return value.isEmpty == false
            && value.hasPrefix("data:") == false
            && value.hasPrefix("blob:") == false
            && value != "#"
    }
}
