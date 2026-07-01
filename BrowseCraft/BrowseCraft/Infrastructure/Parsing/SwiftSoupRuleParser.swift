import Foundation
import SwiftSoup

// 中文注释：SwiftSoupRuleParser.swift 属于网页规则解析实现层，用于说明本文件承载的核心职责。

/// 中文注释：基于 SwiftSoup 的 HTML 规则解析器。
/// 中文注释：SwiftSoup 只出现在这里，应用其他部分都通过 RuleParsingService 使用解析能力。
final class SwiftSoupRuleParser: RuleParsingService {
    private let urlResolver: URLResolvingService

    init(urlResolver: URLResolvingService) {
        self.urlResolver = urlResolver
    }

    /// 中文注释：parseList 方法封装当前类型的一段业务或界面行为。
    func parseList(html: String, source: Source) throws -> [ContentItem] {
        let document: Document = try SwiftSoup.parse(html, source.baseURL)
        let elements: [Element] = try document.select(source.rule.list.item).array()

        var items: [ContentItem] = []

        for element: Element in elements {
            let title: String = try self.extract(element: element, expression: source.rule.list.title)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let link: String = try self.extract(element: element, expression: source.rule.list.link)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // 中文注释：缺少标题或链接的列表项无法在应用中有效展示，直接跳过。
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

    /// 中文注释：parseDetailChapters 方法封装当前类型的一段业务或界面行为。
    func parseDetailChapters(html: String, source: Source, pageURL: String) throws -> [ChapterLink] {
        guard let detailRule: DetailRule = source.rule.detail,
              let chapterItemSelector: String = detailRule.chapterItem,
              let chapterTitleExpression: String = detailRule.chapterTitle,
              let chapterLinkExpression: String = detailRule.chapterLink else {
            return []
        }

        let document: Document = try SwiftSoup.parse(html, pageURL)
        let elements: [Element] = try self.chapterElements(
            in: document,
            source: source,
            detailRule: detailRule,
            chapterItemSelector: chapterItemSelector
        )
        var chapters: [ChapterLink] = []
        var seenURLs: Set<String> = Set<String>()
        var seenTitles: Set<String> = Set<String>()

        for element: Element in elements {
            let title: String = try self.extract(element: element, expression: chapterTitleExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rawURL: String = try self.extract(element: element, expression: chapterLinkExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if title.isEmpty || rawURL.isEmpty {
                continue
            }

            let chapterURL: String = self.urlResolver.absoluteString(rawURL, baseURLString: pageURL)

            if seenURLs.contains(chapterURL) {
                continue
            }

            if seenTitles.contains(title) {
                continue
            }

            seenURLs.insert(chapterURL)
            seenTitles.insert(title)
            chapters.append(
                ChapterLink(
                    title: title,
                    url: chapterURL
                )
            )
        }

        return chapters
    }

    /// 中文注释：chapterElements 方法封装当前类型的一段业务或界面行为。
    private func chapterElements(
        in document: Document,
        source: Source,
        detailRule: DetailRule,
        chapterItemSelector: String
    ) throws -> [Element] {
        if let chapterContainerSelector: String = detailRule.chapterContainer {
            let containers: [Element] = try document.select(chapterContainerSelector).array()

            for container: Element in containers {
                let scopedElements: [Element] = try container.select(chapterItemSelector).array()

                if scopedElements.isEmpty == false {
                    return scopedElements
                }
            }

        }

        return try document.select(chapterItemSelector).array()
    }

    /// 中文注释：parseReader 方法封装当前类型的一段业务或界面行为。
    func parseReader(html: String, source: Source, pageURL: String) throws -> ReaderChapter {
        guard let galleryRule: GalleryRule = source.rule.gallery else {
            return ReaderChapter(
                sourceId: source.id,
                comicTitle: nil,
                chapterTitle: nil,
                chapterURL: pageURL,
                catalogURL: nil,
                previousChapterURL: nil,
                nextChapterURL: nil,
                pageImageURLs: []
            )
        }

        let document: Document = try SwiftSoup.parse(html, pageURL)
        let imageElements: [Element] = try document.select(galleryRule.imageItem).array()
        var pageImageURLs: [String] = []

        for imageElement: Element in imageElements {
            let rawImageURL: String = try self.extract(
                element: imageElement,
                expression: galleryRule.imageUrl
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

            if rawImageURL.isEmpty {
                continue
            }

            let imageURL: String = self.urlResolver.absoluteString(rawImageURL, baseURLString: pageURL)
            pageImageURLs.append(imageURL)
        }

        return ReaderChapter(
            sourceId: source.id,
            comicTitle: try self.optionalExtract(
                element: document,
                expression: galleryRule.comicTitle,
                baseURLString: nil
            ),
            chapterTitle: try self.optionalExtract(
                element: document,
                expression: galleryRule.chapterTitle,
                baseURLString: nil
            ),
            chapterURL: pageURL,
            catalogURL: try self.optionalExtract(
                element: document,
                expression: galleryRule.catalogLink,
                baseURLString: pageURL
            ),
            previousChapterURL: try self.optionalExtract(
                element: document,
                expression: galleryRule.previousLink,
                baseURLString: pageURL
            ),
            nextChapterURL: try self.optionalExtract(
                element: document,
                expression: galleryRule.nextLink,
                baseURLString: pageURL
            ),
            pageImageURLs: pageImageURLs
        )
    }

    /// 中文注释：optionalExtract 方法封装当前类型的一段业务或界面行为。
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

    /// 中文注释：extract 方法封装当前类型的一段业务或界面行为。
    private func extract(element: Element, expression: String) throws -> String {
        if expression == "this" {
            return try element.text()
        }

        if let separatorIndex: String.Index = expression.lastIndex(of: "@") {
            let selector: String = String(expression[..<separatorIndex])
            let attributeExpression: String = String(expression[expression.index(after: separatorIndex)...])
            let selectedElement: Element? = try self.selectedElement(element: element, selector: selector)

            return try self.extractAttribute(element: selectedElement, attributeExpression: attributeExpression)
        }

        return try self.selectedElement(element: element, selector: expression)?.text() ?? ""
    }

    /// 中文注释：selectedElement 方法封装当前类型的一段业务或界面行为。
    private func selectedElement(element: Element, selector: String) throws -> Element? {
        if selector.isEmpty || selector == "this" {
            return element
        }

        if selector == "parent" {
            return element.parent()
        }

        if selector.hasPrefix("parent ") {
            let nestedSelector: String = String(selector.dropFirst("parent ".count))
            return try element.parent()?.select(nestedSelector).first()
        }

        return try element.select(selector).first()
    }

    /// 中文注释：extractAttribute 方法封装当前类型的一段业务或界面行为。
    private func extractAttribute(element: Element?, attributeExpression: String) throws -> String {
        guard let element: Element = element else {
            return ""
        }

        let attributes: [String] = attributeExpression
            .split(separator: "|")
            .map { rawAttribute in
                return String(rawAttribute).trimmingCharacters(in: .whitespacesAndNewlines)
            }

        for attribute: String in attributes {
            let value: String = try element.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)

            if value.isEmpty == false {
                return value
            }
        }

        return ""
    }

    /// 中文注释：stableID 方法封装当前类型的一段业务或界面行为。
    private func stableID(sourceId: String, urlString: String) -> String {
        let rawID: String = "\(sourceId):\(urlString)"
        let data: Data? = rawID.data(using: .utf8)

        return data?.base64EncodedString() ?? UUID().uuidString
    }
}
