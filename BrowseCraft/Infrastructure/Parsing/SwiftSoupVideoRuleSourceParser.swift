import Foundation
import SwiftSoup

// 中文注释：Video V2 的 CSS/DOM 实现物理隔离在 Infrastructure；上层只依赖 VideoRuleSourceParsingService。
final class SwiftSoupVideoRuleSourceParser: VideoRuleSourceParsingService {
    func parseList(
        html: String,
        pageURL: URL,
        rule: VideoListRule
    ) throws -> VideoRuleParsedList {
        let document: Document = try SwiftSoup.parse(html, pageURL.absoluteString)

        if let readyRule: ExtractRule = rule.ready {
            let readyValue: String = try self.extract(
                from: document,
                rule: readyRule,
                pageURL: pageURL
            )
            guard readyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw VideoRuleSourceParsingError.readySelectorEmpty(ruleID: rule.id)
            }
        }

        let candidates: [Element] = try self.selectedElements(from: document, rule: rule.item)
        var items: [VideoRuleParsedListItem] = []
        var seenDetailURLs: Set<String> = []
        var droppedCount: Int = 0

        for candidate: Element in candidates {
            let title: String = try self.extract(
                from: candidate,
                rule: rule.fields.title,
                pageURL: pageURL
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let detailURLString: String = try self.extract(
                from: candidate,
                rule: rule.fields.detailURL,
                pageURL: pageURL
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            guard title.isEmpty == false,
                  let detailURL: URL = self.absoluteHTTPURL(detailURLString, relativeTo: pageURL),
                  seenDetailURLs.insert(detailURL.absoluteString).inserted else {
                droppedCount += 1
                continue
            }

            let idCode: String? = try rule.fields.idCode.flatMap { idRule in
                return try self.optionalExtract(from: candidate, rule: idRule, pageURL: pageURL)
            }
            let coverURL: URL? = try rule.fields.cover.flatMap { coverRule in
                guard let value: String = try self.optionalExtract(
                    from: candidate,
                    rule: coverRule,
                    pageURL: pageURL
                ) else {
                    return nil
                }
                return self.absoluteHTTPURL(value, relativeTo: pageURL)
            }
            let latestText: String? = try rule.fields.latestText.flatMap { latestRule in
                return try self.optionalExtract(from: candidate, rule: latestRule, pageURL: pageURL)
            }

            items.append(
                VideoRuleParsedListItem(
                    idCode: idCode,
                    title: title,
                    detailURL: detailURL,
                    coverURL: coverURL,
                    latestText: latestText
                )
            )
        }

        return VideoRuleParsedList(
            items: items,
            candidateCount: candidates.count,
            droppedCount: droppedCount
        )
    }

    private func optionalExtract(
        from element: Element,
        rule: ExtractRule,
        pageURL: URL
    ) throws -> String? {
        let value: String = try self.extract(from: element, rule: rule, pageURL: pageURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func extract(
        from element: Element,
        rule: ExtractRule,
        pageURL: URL
    ) throws -> String {
        let selectedElement: Element? = try self.selectedElements(from: element, rule: rule).first
        let rawValue: String

        switch rule.function {
        case .text:
            rawValue = try selectedElement?.text() ?? ""
        case .attr:
            rawValue = try self.attributeValue(
                from: selectedElement,
                expression: rule.param ?? ""
            )
        case .raw:
            rawValue = try selectedElement?.outerHtml() ?? ""
        case .url:
            let attributeValue: String = try self.attributeValue(
                from: selectedElement,
                expression: rule.param ?? "href"
            )
            rawValue = self.absoluteURLString(attributeValue, relativeTo: pageURL)
        case .html, .decodeBase64, .removingPercentEncoding, .addingPercentEncoding,
             .replace, .decompressFromBase64, .reversed, .regexReplacement:
            throw VideoRuleSourceParsingError.unsupportedFunction(rule.function)
        }

        let transformedValue: String = try self.applyRegex(
            to: rawValue,
            regex: rule.regex,
            replacement: rule.replacement
        )
        if transformedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return transformedValue
        }

        for fallbackRule: ExtractRule in rule.fallback ?? [] {
            let fallbackValue: String = try self.extract(
                from: element,
                rule: fallbackRule,
                pageURL: pageURL
            )
            if fallbackValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return fallbackValue
            }
        }

        return transformedValue
    }

    private func selectedElements(from element: Element, rule: ExtractRule) throws -> [Element] {
        switch rule.selectorKind {
        case .current:
            return [element]
        case .css:
            guard let selector: String = rule.selector,
                  selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return []
            }
            return try element.select(selector).array()
        case .jsonPath, .xpath:
            throw VideoRuleSourceParsingError.unsupportedSelectorKind(rule.selectorKind ?? .css)
        case .none:
            return []
        }
    }

    private func attributeValue(from element: Element?, expression: String) throws -> String {
        guard let element: Element else {
            return ""
        }

        let attributes: [String] = expression.split(separator: "|").map { value in
            return String(value).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for attribute: String in attributes where attribute.isEmpty == false {
            let value: String = try element.attr(attribute)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty == false {
                return self.cssURLValue(value)
            }
        }
        return ""
    }

    private func cssURLValue(_ value: String) -> String {
        let trimmed: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let openingRange: Range<String.Index> = trimmed.range(
            of: "url(",
            options: .caseInsensitive
        ),
              let closingIndex: String.Index = trimmed[openingRange.upperBound...].firstIndex(of: ")") else {
            return trimmed
        }

        return String(trimmed[openingRange.upperBound..<closingIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private func absoluteURLString(_ rawValue: String, relativeTo pageURL: URL) -> String {
        guard let url: URL = URL(string: self.cssURLValue(rawValue), relativeTo: pageURL)?.absoluteURL else {
            return ""
        }
        return url.absoluteString
    }

    private func absoluteHTTPURL(_ rawValue: String, relativeTo pageURL: URL) -> URL? {
        guard let url: URL = URL(string: self.cssURLValue(rawValue), relativeTo: pageURL)?.absoluteURL,
              let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    private func applyRegex(
        to value: String,
        regex: String?,
        replacement: String?
    ) throws -> String {
        guard let regex: String, regex.isEmpty == false else {
            return value
        }

        let regularExpression: NSRegularExpression = try NSRegularExpression(pattern: regex)
        let range: NSRange = NSRange(value.startIndex..<value.endIndex, in: value)
        if let replacement: String {
            return regularExpression.stringByReplacingMatches(
                in: value,
                range: range,
                withTemplate: replacement
            )
        }

        guard let match: NSTextCheckingResult = regularExpression.firstMatch(in: value, range: range),
              let matchRange: Range<String.Index> = Range(
                  match.range(at: match.numberOfRanges > 1 ? 1 : 0),
                  in: value
              ) else {
            return ""
        }
        return String(value[matchRange])
    }
}
