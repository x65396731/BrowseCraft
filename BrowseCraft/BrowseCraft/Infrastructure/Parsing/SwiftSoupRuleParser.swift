import Foundation
import SwiftSoup

/// HTML rule parser backed by SwiftSoup.
///
/// This class is the only place in the MVP where SwiftSoup appears. The rest of
/// the app depends on RuleParsingService.
final class SwiftSoupRuleParser: RuleParsingService {
    private let urlResolver: URLResolvingService

    init(urlResolver: URLResolvingService) {
        self.urlResolver = urlResolver
    }

    func parseList(html: String, source: Source) throws -> [ContentItem] {
        let document: Document = try SwiftSoup.parse(html, source.baseURL)
        let elements: [Element] = try document.select(source.rule.list.item).array()

        var items: [ContentItem] = []

        for element: Element in elements {
            let title: String = try self.extract(element: element, expression: source.rule.list.title)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let link: String = try self.extract(element: element, expression: source.rule.list.link)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // A list item without title or link is not useful for the app.
            if title.isEmpty || link.isEmpty {
                continue
            }

            let detailURL: String = self.urlResolver.absoluteString(link, baseURLString: source.baseURL)
            let coverURL: String? = try self.optionalExtract(
                element: element,
                expression: source.rule.list.cover,
                baseURLString: source.baseURL
            )
            let latestText: String? = try self.optionalExtract(
                element: element,
                expression: source.rule.list.latestText,
                baseURLString: nil
            )

            let item: ContentItem = ContentItem(
                id: self.stableID(sourceId: source.id, urlString: detailURL),
                sourceId: source.id,
                title: title,
                detailURL: detailURL,
                coverURL: coverURL,
                type: source.rule.list.type,
                latestText: latestText,
                updatedAt: Date()
            )

            items.append(item)
        }

        return items
    }

    private func optionalExtract(
        element: Element,
        expression: String?,
        baseURLString: String?
    ) throws -> String? {
        guard let expression: String = expression else {
            return nil
        }

        let rawValue: String = try self.extract(element: element, expression: expression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if rawValue.isEmpty {
            return nil
        }

        if let baseURLString: String = baseURLString {
            return self.urlResolver.absoluteString(rawValue, baseURLString: baseURLString)
        }

        return rawValue
    }

    private func extract(element: Element, expression: String) throws -> String {
        if expression == "this" {
            return try element.text()
        }

        if let separatorIndex: String.Index = expression.lastIndex(of: "@") {
            let selector: String = String(expression[..<separatorIndex])
            let attribute: String = String(expression[expression.index(after: separatorIndex)...])
            let selectedElement: Element? = try self.selectedElement(element: element, selector: selector)

            return try selectedElement?.attr(attribute) ?? ""
        }

        return try element.select(expression).first()?.text() ?? ""
    }

    private func selectedElement(element: Element, selector: String) throws -> Element? {
        if selector.isEmpty || selector == "this" {
            return element
        }

        return try element.select(selector).first()
    }

    private func stableID(sourceId: String, urlString: String) -> String {
        let rawID: String = "\(sourceId):\(urlString)"
        let data: Data? = rawID.data(using: .utf8)

        return data?.base64EncodedString() ?? UUID().uuidString
    }
}

