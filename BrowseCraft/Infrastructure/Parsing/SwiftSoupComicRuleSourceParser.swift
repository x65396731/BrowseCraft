import Compression
import Foundation
import SwiftSoup

// 中文注释：SwiftSoupComicRuleSourceParser.swift 是 ComicRuleSourceRuntime 专用 SwiftSoup 解析实现。

/// 中文注释：基于 SwiftSoup 的漫画规则 HTML 解析器。
/// 中文注释：漫画规则通过 ComicRuleSourceParsingService 使用它，video 不依赖这个实现。
final class SwiftSoupComicRuleSourceParser: ComicRuleSourceParsingService, ComicRulePaginationParsingService {
    private struct DataChapter: Decodable {
        let id: Int
        let title: String
    }

    private enum ExtractError: LocalizedError {
        case unsupportedFunction(ExtractFunction)
        case unsupportedSelectorKind(SelectorKind)
        case missingRegexReplacementPattern
        case missingReplaceTarget

        var errorDescription: String? {
            switch self {
            case .unsupportedFunction(let function):
                return "Unsupported extract function: \(function.rawValue)"
            case .unsupportedSelectorKind(let selectorKind):
                return "Unsupported selector kind: \(selectorKind.rawValue)"
            case .missingRegexReplacementPattern:
                return "regexReplacement requires a non-empty regex pattern"
            case .missingReplaceTarget:
                return "replace requires a non-empty param target"
            }
        }
    }

    private let urlResolver: URLResolvingService

    init(urlResolver: URLResolvingService) {
        self.urlResolver = urlResolver
    }

    /// 中文注释：parseList 方法封装当前类型的一段业务或界面行为。
    func parseList(html: String, source: Source) throws -> [ContentItem] {
        return try self.parseList(html: html, source: source, listRule: source.rule.primaryListRule)
    }

    func parseList(html: String, source: Source, listRule: ListRule) throws -> [ContentItem] {
        let document: Document = try self.parseListDocument(
            html: html,
            source: source,
            listRule: listRule
        )
        let elements: [Element] = try self.listItemElements(
            in: document,
            selector: listRule.item,
            source: source,
            listRule: listRule
        )
        if elements.isEmpty {
            self.logEmptyListSelectorDiagnostics(
                in: document,
                source: source,
                listRule: listRule
            )
        }
        let items: [ContentItem] = try self.contentItems(
            from: elements,
            source: source,
            listRule: listRule,
            context: nil
        )
        if items.isEmpty == false {
            self.logListSampleItems(
                elements: elements,
                source: source,
                listRule: listRule
            )
        }

        RuleExecutionLogger.log(
            stage: .list,
            event: "selector",
            fields: [
                "source": source.id,
                "listRule": listRule.id ?? "nil",
                "itemSelector": listRule.item,
                "candidateCount": elements.count,
                "count": items.count
            ]
        )

        return items
    }

    func parseList(
        html: String,
        source: Source,
        listRule: ListRule,
        context: ListContext?,
        sections: [SectionRule]?
    ) throws -> [ContentItem] {
        guard let sections: [SectionRule] = sections,
              sections.isEmpty == false else {
            return try self.parseList(html: html, source: source, listRule: listRule).map { item in
                var contextualItem: ContentItem = item
                contextualItem.listContext = context
                return contextualItem
            }
        }

        let document: Document = try self.parseListDocument(
            html: html,
            source: source,
            listRule: listRule
        )
        var items: [ContentItem] = []
        var seenItemIDs: Set<String> = Set<String>()

        for section: SectionRule in sections {
            let containers: [Element] = try self.selectedElements(
                element: document,
                rule: section.container,
                includesSelf: true
            )
            let sectionContext: ListContext = self.listContext(
                base: context,
                section: section,
                listRule: listRule
            )

            for container: Element in containers {
                let elements: [Element] = try self.listItemElements(
                    in: container,
                    selector: listRule.item,
                    source: source,
                    listRule: listRule
                )
                let sectionItems: [ContentItem] = try self.contentItems(
                    from: elements,
                    source: source,
                    listRule: listRule,
                    context: sectionContext
                )

                for item: ContentItem in sectionItems where seenItemIDs.contains(item.id) == false {
                    seenItemIDs.insert(item.id)
                    items.append(item)
                }
            }
        }

        return items
    }

    func parseSearch(
        html: String,
        source: Source,
        searchRule: SearchRule,
        context: ListContext?
    ) throws -> [ContentItem] {
        let document: Document = try SwiftSoup.parse(html, source.baseURL)
        let elements: [Element] = try self.selectedElements(
            element: document,
            rule: searchRule.item,
            includesSelf: false
        )
        let items: [ContentItem] = try self.searchContentItems(
            from: elements,
            source: source,
            searchRule: searchRule,
            context: context
        )

        RuleExecutionLogger.log(
            stage: .search,
            event: "search-selector",
            fields: [
                "source": source.id,
                "searchRule": searchRule.id ?? "nil",
                "candidateCount": elements.count,
                "count": items.count
            ]
        )

        return items
    }

    func parseNextPageURL(
        html: String,
        source: Source,
        pagination: PaginationRule,
        currentURL: URL
    ) throws -> String? {
        guard let nextPageRule: ExtractRule = pagination.nextPage else {
            return nil
        }

        let document: Document = try SwiftSoup.parse(html, currentURL.absoluteString)
        return try self.optionalExtract(
            element: document,
            rule: nextPageRule,
            baseURLString: currentURL.absoluteString
        )
    }

    private func contentItems(
        from elements: [Element],
        source: Source,
        listRule: ListRule,
        context: ListContext?
    ) throws -> [ContentItem] {
        var items: [ContentItem] = []
        var droppedCount: Int = 0
        var loggedDropSamples: Int = 0

        for (index, element) in elements.enumerated() {
            let title: String
            let link: String
            do {
                title = try self.extract(element: element, expression: listRule.title)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                link = try self.extract(element: element, expression: listRule.link)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                RuleExecutionLogger.log(
                    stage: .list,
                    event: "item-extract-error",
                    fields: [
                        "source": source.id,
                        "listRule": listRule.id ?? "nil",
                        "index": index,
                        "titleSelector": listRule.title,
                        "linkSelector": listRule.link,
                        "error": error.localizedDescription,
                        "elementPreview": self.elementPreview(element)
                    ]
                )
                throw error
            }

            // 中文注释：缺少标题或链接的列表项无法在应用中有效展示，直接跳过。
            if title.isEmpty || link.isEmpty {
                droppedCount += 1
                if loggedDropSamples < 3 {
                    loggedDropSamples += 1
                    RuleExecutionLogger.log(
                        stage: .list,
                        event: "item-dropped",
                        fields: [
                            "source": source.id,
                            "listRule": listRule.id ?? "nil",
                            "index": index,
                            "titleEmpty": title.isEmpty,
                            "linkEmpty": link.isEmpty,
                            "titleSelector": listRule.title,
                            "linkSelector": listRule.link,
                            "titlePreview": self.shortPreview(title),
                            "linkPreview": self.shortPreview(link),
                            "elementPreview": self.elementPreview(element)
                        ]
                    )
                }
                continue
            }

            let detailURL: String = self.urlResolver.absoluteString(link, baseURLString: source.baseURL)
            let coverURL: String? = self.optionalListField(
                element: element,
                expression: listRule.cover,
                baseURLString: source.baseURL,
                field: "cover",
                source: source,
                listRule: listRule,
                index: index
            )
            let latestText: String? = self.optionalListField(
                element: element,
                expression: listRule.latestText,
                baseURLString: nil,
                field: "latestText",
                source: source,
                listRule: listRule,
                index: index
            )

            let item: ContentItem = ContentItem(
                id: self.stableID(sourceId: source.id, urlString: detailURL),
                sourceId: source.id,
                title: title,
                detailURL: detailURL,
                coverURL: coverURL,
                type: listRule.type,
                latestText: latestText,
                updatedAt: Date(),
                listOrder: items.count,
                listContext: context
            )

            items.append(item)
        }

        if droppedCount > 0 {
            RuleExecutionLogger.log(
                stage: .list,
                event: "item-drop-summary",
                fields: [
                    "source": source.id,
                    "listRule": listRule.id ?? "nil",
                    "candidateCount": elements.count,
                    "droppedCount": droppedCount,
                    "acceptedCount": items.count
                ]
            )
        }

        return items
    }

    private func optionalListField(
        element: Element,
        expression: String?,
        baseURLString: String?,
        field: String,
        source: Source,
        listRule: ListRule,
        index: Int
    ) -> String? {
        do {
            return try self.optionalExtract(
                element: element,
                expression: expression,
                baseURLString: baseURLString
            )
        } catch {
            RuleExecutionLogger.log(
                stage: .list,
                event: "item-optional-field-error",
                fields: [
                    "source": source.id,
                    "listRule": listRule.id ?? "nil",
                    "index": index,
                    "field": field,
                    "expression": expression ?? "nil",
                    "error": error.localizedDescription,
                    "elementPreview": self.elementPreview(element)
                ]
            )
            return nil
        }
    }

    private func elementPreview(_ element: Element) -> String {
        let html: String = (try? element.outerHtml()) ?? ""
        return self.shortPreview(html)
    }

    private func shortPreview(_ value: String, limit: Int = 180) -> String {
        let normalized: String = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count > limit else {
            return normalized
        }

        return String(normalized.prefix(limit))
    }

    private func searchContentItems(
        from elements: [Element],
        source: Source,
        searchRule: SearchRule,
        context: ListContext?
    ) throws -> [ContentItem] {
        var items: [ContentItem] = []
        let contentType: SourceContentKind = self.searchContentType(source: source, searchRule: searchRule)

        for element: Element in elements {
            let title: String = try self.extract(element: element, rule: searchRule.fields.title)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rawDetailURL: String = try self.extract(element: element, rule: searchRule.fields.detailURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // 中文注释：搜索结果和列表项一样，缺少标题或详情链接时无法进入后续详情/阅读流程。
            if title.isEmpty || rawDetailURL.isEmpty {
                continue
            }

            let detailURL: String = self.urlResolver.absoluteString(rawDetailURL, baseURLString: source.baseURL)
            let coverURL: String? = try self.optionalExtract(
                element: element,
                rule: searchRule.fields.cover,
                baseURLString: source.baseURL
            )
            let latestText: String? = try self.optionalExtract(
                element: element,
                rule: searchRule.fields.latestText,
                baseURLString: nil
            )

            items.append(
                ContentItem(
                    id: self.stableID(sourceId: source.id, urlString: detailURL),
                    sourceId: source.id,
                    title: title,
                    detailURL: detailURL,
                    coverURL: coverURL,
                    type: contentType,
                    latestText: latestText,
                    updatedAt: Date(),
                    listOrder: items.count,
                    listContext: context
                )
            )
        }

        return items
    }

    private func searchContentType(source: Source, searchRule: SearchRule) -> SourceContentKind {
        if let listRule: ListRule = source.rule.ruleSets?.listRule(id: searchRule.listRuleRef) {
            return listRule.type
        }

        return source.rule.primaryListRule.type
    }

    private func listContext(base: ListContext?, section: SectionRule, listRule: ListRule) -> ListContext {
        return ListContext(
            pageId: base?.pageId,
            tabId: base?.tabId,
            sectionId: section.id,
            listRuleId: section.listRuleRef ?? base?.listRuleId ?? listRule.id,
            sectionRole: section.role ?? base?.sectionRole ?? .main
        )
    }

    /// 中文注释：parseDetailChapters 方法封装当前类型的一段业务或界面行为。
    func parseDetailChapters(html: String, source: Source, pageURL: String) throws -> [ChapterLink] {
        return try self.parseDetailChapters(
            html: html,
            source: source,
            pageURL: pageURL,
            context: nil
        )
    }

    func parseDetailChapters(
        html: String,
        source: Source,
        pageURL: String,
        context: ListContext?
    ) throws -> [ChapterLink] {
        let resolvedRule: ResolvedSiteRule = RuleResolver().resolve(source.rule)
        guard let detailRule: DetailRule = resolvedRule.primaryDetailRule else {
            return []
        }

        return try self.parseDetailChapters(
            html: html,
            source: source,
            detailRule: detailRule,
            pageURL: pageURL,
            context: context
        )
    }

    func parseDetailChapters(
        html: String,
        source: Source,
        detailRule: DetailRule,
        pageURL: String,
        context: ListContext?
    ) throws -> [ChapterLink] {
        RuleExecutionLogger.log(
            stage: .detail,
            event: "document-parse-attempt",
            fields: [
                "source": source.id,
                "pageURL": pageURL,
                "htmlLength": html.count
            ]
        )
        let document: Document = try SwiftSoup.parse(html, pageURL)

        if let chapterRule: ChapterRule = detailRule.chapterRule {
            // 中文注释：优先读取页面内的结构化章节数据。部分站点会把真实章节放在 x-data/JSON 中，
            // 中文注释：原始 HTML 里的普通 a 标签可能只是排行或推荐区，不能作为主章节列表。
            let dataChapters: [ChapterLink] = try self.dataChapterLinks(
                in: document,
                source: source,
                detailRule: detailRule,
                chapterRule: chapterRule,
                context: context,
                pageURL: pageURL
            )

            if dataChapters.isEmpty == false {
                return dataChapters
            }

            let elements: [Element] = try self.chapterElements(
                in: document,
                detailRule: detailRule,
                chapterRule: chapterRule,
                context: context
            )

            RuleExecutionLogger.log(
                stage: .detail,
                event: "selector-v2",
                fields: [
                    "source": source.id,
                    "pageURL": pageURL,
                    "section": context?.sectionId ?? "nil",
                    "elementCount": elements.count
                ]
            )
            if elements.isEmpty {
                self.logEmptyChapterSelectorDiagnostics(
                    in: document,
                    source: source,
                    detailRule: detailRule,
                    chapterItemSelector: chapterRule.item.selector ?? "nil",
                    pageURL: pageURL
                )
            }

            return try self.chapterLinks(
                from: elements,
                titleRule: chapterRule.title,
                urlRule: chapterRule.url,
                pageURL: pageURL
            )
        }

        guard let chapterItemSelector: String = detailRule.chapterItem,
              let chapterTitleExpression: String = detailRule.chapterTitle,
              let chapterLinkExpression: String = detailRule.chapterLink else {
            return []
        }

        let elements: [Element] = try self.chapterElements(
            in: document,
            source: source,
            detailRule: detailRule,
            chapterItemSelector: chapterItemSelector
        )

        let globalChapterLinkCount: Int = try document.select(chapterItemSelector).array().count
        RuleExecutionLogger.log(
            stage: .detail,
            event: "selector-legacy",
            fields: [
                "source": source.id,
                "pageURL": pageURL,
                "chapterContainer": detailRule.chapterContainer ?? "nil",
                "chapterItem": chapterItemSelector,
                "htmlHasChapterLinks": html.contains("/cn/chapters/"),
                "globalChapterLinkCount": globalChapterLinkCount,
                "elementCount": elements.count
            ]
        )
        if elements.isEmpty {
            self.logEmptyChapterSelectorDiagnostics(
                in: document,
                source: source,
                detailRule: detailRule,
                chapterItemSelector: chapterItemSelector,
                pageURL: pageURL
            )
        }

        let titleRule: ExtractRule = ExtractRule(
            selector: chapterTitleExpression,
            function: .text,
            param: nil,
            regex: nil,
            replacement: nil,
            fallback: nil
        )
        let urlRule: ExtractRule = self.extractRule(fromLegacyExpression: chapterLinkExpression)

        return try self.chapterLinks(
            from: elements,
            titleRule: titleRule,
            urlRule: urlRule,
            pageURL: pageURL
        )
    }

    func parseDetailDescription(
        html: String,
        source: Source,
        detailRule: DetailRule,
        pageURL: String,
        context: ListContext?
    ) throws -> String? {
        let document: Document = try SwiftSoup.parse(html, pageURL)
        let scope: Element = try self.contextualScope(
            in: document,
            mainScopeRule: detailRule.mainScope,
            context: context
        ) ?? document

        if let descriptionRule: ExtractRule = detailRule.fields?.description {
            let rawDescription: String = try self.extract(element: scope, rule: descriptionRule)

            if let description: String = self.sanitizedDetailDescription(rawDescription) {
                return description
            }
        }

        return nil
    }

    private func sanitizedDetailDescription(_ value: String) -> String? {
        let collapsedValue: String = value
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { line in
                return line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                return line.isEmpty == false
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsedValue.count >= 8,
              self.isNoisyDetailDescription(collapsedValue) == false else {
            return nil
        }

        return collapsedValue
    }

    private func isNoisyDetailDescription(_ value: String) -> Bool {
        let lowercaseValue: String = value.lowercased()
        let noisyFragments: [String] = [
            "attention required",
            "cloudflare",
            "please enable cookies",
            "you have been blocked",
            "mycomic",
            "browsecraft"
        ]

        if noisyFragments.contains(where: { fragment in lowercaseValue == fragment }) {
            return true
        }

        return lowercaseValue.hasPrefix("attention required")
            || lowercaseValue.hasPrefix("just a moment")
    }

    private func chapterLinks(
        from elements: [Element],
        titleRule: ExtractRule,
        urlRule: ExtractRule,
        pageURL: String
    ) throws -> [ChapterLink] {
        var chapters: [ChapterLink] = []
        var seenURLs: Set<String> = Set<String>()

        for element: Element in elements {
            let title: String = try self.extract(element: element, rule: titleRule)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rawURL: String = try self.extract(element: element, rule: urlRule)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if title.isEmpty || rawURL.isEmpty {
                continue
            }

            let chapterURL: String = self.urlResolver.absoluteString(rawURL, baseURLString: pageURL)

            if seenURLs.contains(chapterURL) {
                continue
            }

            // 中文注释：只按 URL 去重。标题可能在不同分组里重复，例如“第01话”和番外/卷册并存。
            seenURLs.insert(chapterURL)
            chapters.append(
                ChapterLink(
                    title: title,
                    url: chapterURL
                )
            )
        }

        #if DEBUG
        print("[BrowseCraftRule] Parsed chapterCount=\(chapters.count) page=\(pageURL)")

        for (index, chapter) in chapters.enumerated() {
            print(
                "[BrowseCraftRule] Parsed chapter " +
                "page=\(pageURL) " +
                "index=\(index) " +
                "title=\(chapter.title) " +
                "url=\(chapter.url)"
            )
        }
        #endif

        return chapters
    }

    private func dataChapterLinks(
        in document: Document,
        source: Source,
        detailRule: DetailRule,
        chapterRule: ChapterRule,
        context: ListContext?,
        pageURL: String
    ) throws -> [ChapterLink] {
        guard let idCodeRule: ExtractRule = chapterRule.idCode else {
            return []
        }

        let scope: Element = try self.contextualScope(
            in: document,
            mainScopeRule: detailRule.mainScope,
            context: context
        ) ?? document

        let containers: [Element]

        if let section: SectionRule = chapterRule.section {
            containers = try self.selectedElements(
                element: scope,
                rule: section.container,
                includesSelf: true
            )
        } else {
            containers = [scope]
        }

        var chapters: [ChapterLink] = []
        var seenIDs: Set<Int> = Set<Int>()
        let chapterURLPrefix: String = self.chapterURLPrefix(source: source, pageURL: pageURL)

        for container: Element in containers {
            // 中文注释：每个 container 对应一个源站章节分组，例如单话、单行本、番外篇。
            // 中文注释：遍历顺序即源站展示顺序，后续 UI 先保持这个顺序，避免跨分组自然排序导致混排。
            let rawData: String = try self.extract(element: container, rule: idCodeRule)
            let dataChapters: [DataChapter]?

            do {
                dataChapters = try self.dataChapters(from: rawData)
            } catch {
                #if DEBUG
                print(
                    "[BrowseCraftRule] Parse data chapters failed " +
                    "page=\(pageURL) " +
                    "error=\(error)"
                )
                #endif

                continue
            }

            guard let dataChapters: [DataChapter] = dataChapters else {
                continue
            }

            #if DEBUG
            let sectionTitle: String = try self.dataChapterSectionTitle(from: container)
            let countBeforeSection: Int = chapters.count
            #endif

            for dataChapter: DataChapter in dataChapters {
                if seenIDs.contains(dataChapter.id) {
                    continue
                }

                // 中文注释：结构化章节里 id 是比标题更稳定的唯一键。
                seenIDs.insert(dataChapter.id)
                chapters.append(
                    ChapterLink(
                        title: dataChapter.title,
                        url: "\(chapterURLPrefix)/\(dataChapter.id)"
                    )
                )
            }

            #if DEBUG
            let addedCount: Int = chapters.count - countBeforeSection
            print(
                "[BrowseCraftRule] Parsed data chapter section " +
                "page=\(pageURL) " +
                "section=\(sectionTitle) " +
                "rawCount=\(dataChapters.count) " +
                "addedCount=\(addedCount) " +
                "firstTitle=\(dataChapters.first?.title ?? "nil") " +
                "lastTitle=\(dataChapters.last?.title ?? "nil")"
            )
            #endif
        }

        #if DEBUG
        print(
            "[BrowseCraftRule] Parsed data chapters " +
            "page=\(pageURL) " +
            "containerCount=\(containers.count) " +
            "chapterCount=\(chapters.count) " +
            "firstURL=\(chapters.first?.url ?? "nil")"
        )
        #endif

        return chapters
    }

    private func dataChapterSectionTitle(from element: Element) throws -> String {
        let rawText: String = try element.text()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard rawText.isEmpty == false else {
            return "unknown"
        }

        // 中文注释：当前用于 DEBUG 对账。标题通常位于“倒序排列/升序排列”控件之前。
        let markers: [String] = ["倒序排列", "升序排列"]

        for marker: String in markers {
            if let markerRange: Range<String.Index> = rawText.range(of: marker) {
                let title: String = String(rawText[..<markerRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if title.isEmpty == false {
                    return title
                }
            }
        }

        return String(rawText.prefix(24))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dataChapters(from rawData: String) throws -> [DataChapter]? {
        guard let arrayString: String = self.bracketedArray(
            in: rawData,
            after: "chapters"
        ) else {
            return nil
        }

        let data: Data = Data(arrayString.utf8)

        return try JSONDecoder().decode([DataChapter].self, from: data)
    }

    private func bracketedArray(in value: String, after marker: String) -> String? {
        // 中文注释：x-data 是 JavaScript 对象片段，不是完整 JSON；这里只截取 marker 后的数组部分再交给 JSONDecoder。
        guard let markerRange: Range<String.Index> = value.range(of: marker),
              let startIndex: String.Index = value[markerRange.upperBound...].firstIndex(of: "[") else {
            return nil
        }

        var depth: Int = 0
        var isInsideString: Bool = false
        var isEscaped: Bool = false
        var currentIndex: String.Index = startIndex

        while currentIndex < value.endIndex {
            let character: Character = value[currentIndex]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1

                if depth == 0 {
                    return String(value[startIndex...currentIndex])
                }
            }

            currentIndex = value.index(after: currentIndex)
        }

        return nil
    }

    private func chapterURLPrefix(source: Source, pageURL: String) -> String {
        if let comicsRange: Range<String.Index> = pageURL.range(of: "/comics/") {
            return "\(pageURL[..<comicsRange.lowerBound])/chapters"
        }

        return "\(source.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/chapters"
    }

    private func chapterElements(
        in document: Document,
        detailRule: DetailRule,
        chapterRule: ChapterRule,
        context: ListContext?
    ) throws -> [Element] {
        let scope: Element = try self.contextualScope(
            in: document,
            mainScopeRule: detailRule.mainScope,
            context: context
        ) ?? document

        let containerScopes: [Element]

        if let section: SectionRule = chapterRule.section {
            containerScopes = try self.selectedElements(
                element: scope,
                rule: section.container,
                includesSelf: true
            )
        } else {
            containerScopes = [scope]
        }

        var elements: [Element] = []

        for containerScope: Element in containerScopes {
            elements.append(
                contentsOf: try self.selectedElements(
                    element: containerScope,
                    rule: chapterRule.item
                )
            )
        }

        let filteredElements: [Element] = try self.filteredElements(
            elements,
            excluding: detailRule.exclude ?? [],
            in: scope
        )

        #if DEBUG
        print(
            "[BrowseCraftRule] V2 chapter candidates " +
            "beforeFilter=\(elements.count) " +
            "afterFilter=\(filteredElements.count)"
        )
        #endif

        return filteredElements
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
            var elements: [Element] = []

            for container: Element in containers {
                let scopedElements: [Element] = try container.select(chapterItemSelector).array()

                elements.append(contentsOf: scopedElements)
            }

            if elements.isEmpty == false {
                return elements
            }

            #if DEBUG
            print(
                "[BrowseCraftRule] Chapter container matched no chapter items; skip global fallback " +
                "chapterContainer=\(chapterContainerSelector) chapterItem=\(chapterItemSelector)"
            )
            #endif

            return []
        }

        return try document.select(chapterItemSelector).array()
    }

    private func logEmptyChapterSelectorDiagnostics(
        in document: Document,
        source: Source,
        detailRule: DetailRule,
        chapterItemSelector: String,
        pageURL: String
    ) {
        RuleExecutionLogger.log(
            stage: .detail,
            event: "chapter-selector-empty-diagnostics",
            fields: [
                "source": source.id,
                "pageURL": pageURL,
                "chapterContainer": detailRule.chapterContainer ?? detailRule.chapterRule?.section?.container.selector ?? "nil",
                "chapterItem": chapterItemSelector,
                "topClasses": self.topClassSummary(in: document).joined(separator: "|"),
                "chapterLinkSamples": self.chapterLinkSamples(in: document).joined(separator: "|")
            ]
        )
    }

    private func chapterLinkSamples(in element: Element) -> [String] {
        let links: [Element] = (try? element.select("a[href]").array()) ?? []
        var samples: [String] = []
        var seen: Set<String> = Set<String>()

        for link: Element in links {
            guard samples.count < 12 else {
                break
            }

            let href: String = ((try? link.attr("href")) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let text: String = ((try? link.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title: String = ((try? link.attr("title")) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let label: String = text.isEmpty ? title : text

            guard href.isEmpty == false,
                  href.hasPrefix("#") == false,
                  self.looksLikeChapterHref(href) || self.looksLikeChapterTitle(label) else {
                continue
            }

            let sample: String = label.isEmpty
                ? self.shortPreview(href, limit: 120)
                : "\(self.shortPreview(label, limit: 50))=>\(self.shortPreview(href, limit: 120))"
            guard seen.contains(sample) == false else {
                continue
            }

            seen.insert(sample)
            samples.append(sample)
        }

        return samples
    }

    private func looksLikeChapterHref(_ href: String) -> Bool {
        let lowercaseHref: String = href.lowercased()
        return lowercaseHref.contains("/chapter")
            || lowercaseHref.contains("-chapter-")
            || lowercaseHref.contains("/chapters/")
            || lowercaseHref.contains("/read/")
            || lowercaseHref.contains("/reader/")
    }

    private func fallbackChapterElements(
        in document: Document,
        chapterItemSelector: String
    ) throws -> [Element] {
        let allChapterElements: [Element] = try document.select(chapterItemSelector).array()

        for element: Element in allChapterElements {
            let title: String = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)

            if self.looksLikeChapterTitle(title) == false {
                continue
            }

            var currentElement: Element? = element.parent()

            while let ancestor: Element = currentElement {
                let scopedElements: [Element] = try ancestor.select(chapterItemSelector).array()
                let chapterLikeElements: [Element] = try scopedElements.filter { scopedElement in
                    let scopedTitle: String = try scopedElement.text()
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    return self.looksLikeChapterTitle(scopedTitle)
                }

                if chapterLikeElements.count >= 2 {
                    #if DEBUG
                    print(
                        "[BrowseCraftRule] Fallback chapter group " +
                        "ancestor=\(ancestor.tagName()) " +
                        "count=\(chapterLikeElements.count) " +
                        "firstTitle=\(try chapterLikeElements.first?.text() ?? "nil")"
                    )
                    #endif

                    return chapterLikeElements
                }

                currentElement = ancestor.parent()
            }
        }

        #if DEBUG
        print("[BrowseCraftRule] Fallback chapter group not found")
        #endif

        return []
    }

    private func looksLikeChapterTitle(_ title: String) -> Bool {
        let normalizedTitle: String = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedTitle.isEmpty {
            return false
        }

        if normalizedTitle.contains("开始阅读") || normalizedTitle.contains("開始閱讀") {
            return false
        }

        return normalizedTitle.contains("第")
            && (normalizedTitle.contains("话") || normalizedTitle.contains("話"))
    }

    /// 中文注释：parseReader 方法封装当前类型的一段业务或界面行为。
    func parseReader(html: String, source: Source, pageURL: String) throws -> ReaderChapter {
        return try self.parseReader(
            html: html,
            source: source,
            pageURL: pageURL,
            context: nil
        )
    }

    func parseReader(
        html: String,
        source: Source,
        pageURL: String,
        context: ListContext?
    ) throws -> ReaderChapter {
        let resolvedRule: ResolvedSiteRule = RuleResolver().resolve(source.rule)
        guard let galleryRule: GalleryRule = resolvedRule.primaryGalleryRule else {
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

        return try self.parseReader(
            html: html,
            source: source,
            galleryRule: galleryRule,
            pageURL: pageURL,
            context: context
        )
    }

    func parseReader(
        html: String,
        source: Source,
        galleryRule: GalleryRule,
        pageURL: String,
        context: ListContext?
    ) throws -> ReaderChapter {
        let document: Document = try SwiftSoup.parse(html, pageURL)
        let scope: Element = try self.contextualScope(
            in: document,
            mainScopeRule: galleryRule.mainScope,
            context: context
        ) ?? document
        let imageElements: [Element] = try scope.select(galleryRule.imageItem).array()
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

        RuleExecutionLogger.log(
            stage: .reader,
            event: "selector",
            fields: [
                "source": source.id,
                "pageURL": pageURL,
                "section": context?.sectionId ?? "nil",
                "imageItem": galleryRule.imageItem,
                "candidateCount": imageElements.count,
                "count": pageImageURLs.count,
                "firstImage": pageImageURLs.first ?? "nil"
            ]
        )

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

    private func optionalExtract(
        element: Element,
        rule: ExtractRule?,
        baseURLString: String?
    ) throws -> String? {
        guard let rule: ExtractRule = rule else {
            return nil
        }

        let rawValue: String = try self.extract(element: element, rule: rule)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if rawValue.isEmpty {
            return nil
        }

        if let baseURLString: String = baseURLString {
            return self.urlResolver.absoluteString(rawValue, baseURLString: baseURLString)
        }

        return rawValue
    }

    private func scopedElement(in document: Document, scopeRule: ExtractRule?) throws -> Element? {
        guard let scopeRule: ExtractRule = scopeRule else {
            return document
        }

        return try self.selectedElements(element: document, rule: scopeRule).first
    }

    private func contextualScope(
        in document: Document,
        mainScopeRule: ExtractRule?,
        context: ListContext?
    ) throws -> Element? {
        let baseScope: Element = try self.scopedElement(
            in: document,
            scopeRule: mainScopeRule
        ) ?? document

        // 中文注释：P1-5.3 只在 mainScope 内根据来源 context 继续缩小范围；匹配不到时保留旧规则行为。
        guard let context: ListContext = context else {
            return baseScope
        }

        for selector: String in self.contextScopeSelectors(context: context) {
            if let scopedElement: Element = try baseScope.select(selector).array().first {
                return scopedElement
            }
        }

        return baseScope
    }

    private func contextScopeSelectors(context: ListContext) -> [String] {
        var selectors: [String] = []

        if let sectionId: String = context.sectionId,
           sectionId.isEmpty == false {
            let quotedSectionId: String = self.cssQuotedValue(sectionId)
            selectors.append("[data-section-id=\"\(quotedSectionId)\"]")
            selectors.append("[data-section=\"\(quotedSectionId)\"]")

            if self.isSimpleCSSIdentifier(sectionId) {
                selectors.append("#\(sectionId)")
                selectors.append(".\(sectionId)")
            }
        }

        if let sectionRole: SectionRole = context.sectionRole {
            let roleValue: String = sectionRole.rawValue
            selectors.append("[data-section-role=\"\(roleValue)\"]")
            selectors.append("[data-role=\"\(roleValue)\"]")

            if self.isSimpleCSSIdentifier(roleValue) {
                selectors.append("section.\(roleValue)")
                selectors.append(".\(roleValue)")
            }
        }

        return selectors
    }

    private func cssQuotedValue(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func isSimpleCSSIdentifier(_ value: String) -> Bool {
        guard value.isEmpty == false else {
            return false
        }

        return value.allSatisfy { character in
            return character.isLetter || character.isNumber || character == "-" || character == "_"
        }
    }

    private func selectedElements(
        element: Element,
        rule: ExtractRule,
        includesSelf: Bool = false
    ) throws -> [Element] {
        switch rule.selectorKind {
        case .current:
            return [element]
        case .jsonPath:
            throw ExtractError.unsupportedSelectorKind(.jsonPath)
        case .xpath:
            throw ExtractError.unsupportedSelectorKind(.xpath)
        case .css,
             .none:
            break
        }

        guard let selector: String = rule.selector,
              selector.isEmpty == false,
              selector != "this" else {
            return [element]
        }

        if selector == "parent" {
            return element.parent().map { parent in
                return [parent]
            } ?? []
        }

        if selector.hasPrefix("parent ") {
            let nestedSelector: String = String(selector.dropFirst("parent ".count))
            guard let parent: Element = element.parent() else {
                return []
            }

            return try parent.select(nestedSelector).array()
        }

        var elements: [Element] = []

        if includesSelf,
           try element.iS(selector) {
            elements.append(element)
        }

        for selectedElement: Element in try element.select(selector).array() {
            let selectedHTML: String = try selectedElement.outerHtml()
            let alreadyIncluded: Bool = try elements.contains { element in
                return try element.outerHtml() == selectedHTML
            }

            if alreadyIncluded == false {
                elements.append(selectedElement)
            }
        }

        return elements
    }

    private func parseListDocument(
        html: String,
        source: Source,
        listRule: ListRule
    ) throws -> Document {
        RuleExecutionLogger.log(
            stage: .list,
            event: "document-parse-attempt",
            fields: [
                "source": source.id,
                "listRule": listRule.id ?? "nil",
                "htmlLength": html.count,
                "baseURL": source.baseURL
            ]
        )

        do {
            return try SwiftSoup.parse(html, source.baseURL)
        } catch {
            RuleExecutionLogger.log(
                stage: .list,
                event: "document-parse-error",
                fields: [
                    "source": source.id,
                    "listRule": listRule.id ?? "nil",
                    "error": error.localizedDescription,
                    "htmlPreview": self.shortPreview(html)
                ]
            )

            let sanitizedHTML: String = html.replacingOccurrences(of: "\u{0000}", with: "")
            guard sanitizedHTML != html else {
                throw error
            }

            do {
                let document: Document = try SwiftSoup.parse(sanitizedHTML, source.baseURL)
                RuleExecutionLogger.log(
                    stage: .list,
                    event: "document-parse-recovered",
                    fields: [
                        "source": source.id,
                        "listRule": listRule.id ?? "nil",
                        "removedNullBytes": true
                    ]
                )
                return document
            } catch {
                throw error
            }
        }
    }

    private func listItemElements(
        in element: Element,
        selector: String,
        source: Source,
        listRule: ListRule
    ) throws -> [Element] {
        let selectorParts: [String] = self.topLevelSelectorParts(selector)
        if selectorParts.count > 1 {
            return try self.listItemElements(
                in: element,
                selectorParts: selectorParts,
                originalSelector: selector,
                source: source,
                listRule: listRule
            )
        }

        do {
            return try element.select(selector).array()
        } catch {
            RuleExecutionLogger.log(
                stage: .list,
                event: "item-selector-error",
                fields: [
                    "source": source.id,
                    "listRule": listRule.id ?? "nil",
                    "selector": selector,
                    "error": error.localizedDescription
                ]
            )
            throw error
        }
    }

    private func listItemElements(
        in element: Element,
        selectorParts: [String],
        originalSelector: String,
        source: Source,
        listRule: ListRule
    ) throws -> [Element] {
        var elements: [Element] = []
        var seenHTML: Set<String> = Set<String>()
        var failedSelectors: [String] = []
        var matchedSelectors: [String] = []
        var firstError: Error?

        for selectorPart: String in selectorParts {
            do {
                let selectedElements: [Element] = try element.select(selectorPart).array()

                if selectedElements.isEmpty == false {
                    matchedSelectors.append("\(selectorPart):\(selectedElements.count)")
                }

                for selectedElement: Element in selectedElements {
                    let selectedHTML: String = (try? selectedElement.outerHtml()) ?? ""
                    guard seenHTML.contains(selectedHTML) == false else {
                        continue
                    }

                    seenHTML.insert(selectedHTML)
                    elements.append(selectedElement)
                }
            } catch {
                if firstError == nil {
                    firstError = error
                }
                failedSelectors.append(selectorPart)
            }
        }

        RuleExecutionLogger.log(
            stage: .list,
            event: "item-selector-parts",
            fields: [
                "source": source.id,
                "listRule": listRule.id ?? "nil",
                "selector": originalSelector,
                "matchedSelectors": matchedSelectors.joined(separator: "|"),
                "failedSelectors": failedSelectors.joined(separator: "|"),
                "count": elements.count
            ]
        )

        if elements.isEmpty,
           failedSelectors.count == selectorParts.count,
           let firstError: Error = firstError {
            throw firstError
        }

        return elements
    }

    private func logListSampleItems(
        elements: [Element],
        source: Source,
        listRule: ListRule
    ) {
        RuleExecutionLogger.log(
            stage: .list,
            event: "sample-items",
            fields: [
                "source": source.id,
                "listRule": listRule.id ?? "nil",
                "selector": listRule.item,
                "sampleItems": self.listSampleItems(
                    elements: elements,
                    source: source,
                    listRule: listRule
                ).joined(separator: " || ")
            ]
        )
    }

    private func listSampleItems(
        elements: [Element],
        source: Source,
        listRule: ListRule
    ) -> [String] {
        var samples: [String] = []

        for (index, element) in elements.enumerated() {
            guard samples.count < 3 else {
                break
            }

            let title: String = ((try? self.extract(element: element, expression: listRule.title)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let link: String = ((try? self.extract(element: element, expression: listRule.link)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.isEmpty == false,
                  link.isEmpty == false else {
                continue
            }

            let detailURL: String = self.urlResolver.absoluteString(link, baseURLString: source.baseURL)
            samples.append(
                [
                    "index=\(index)",
                    "itemClass=\(self.itemClassSample(element))",
                    "title=\(self.shortPreview(title, limit: 60))",
                    "link=\(self.shortPreview(detailURL, limit: 120))",
                    "coverAttrs=\(self.coverAttributeSample(element))",
                    "latestCandidates=\(self.latestTextCandidateSample(element, listRule: listRule))"
                ].joined(separator: ";")
            )
        }

        return samples
    }

    private func itemClassSample(_ element: Element) -> String {
        let className: String = ((try? element.className()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return className.isEmpty ? "nil" : self.shortPreview(className, limit: 80)
    }

    private func coverAttributeSample(_ element: Element) -> String {
        guard let image: Element = try? element.select("img").first() else {
            return "nil"
        }

        let attrs: [String] = [
            "src",
            "data-src",
            "data-original",
            "data-lazy-src",
            "data-manga-src"
        ].compactMap { attributeName in
            let value: String = ((try? image.attr(attributeName)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty == false else {
                return nil
            }

            return "\(attributeName)=\(self.shortPreview(value, limit: 80))"
        }

        return attrs.isEmpty ? "nil" : attrs.joined(separator: ",")
    }

    private func latestTextCandidateSample(_ element: Element, listRule: ListRule) -> String {
        var candidates: [String] = []
        if let latestText: String = try? self.optionalExtract(
            element: element,
            expression: listRule.latestText,
            baseURLString: nil
        ) {
            candidates.append("rule=\(self.shortPreview(latestText, limit: 60))")
        }

        let selectors: [String] = [
            ".mg_chapter",
            ".chapter",
            ".latest",
            ".latest-chap",
            ".post-on",
            ".chapter_count",
            "time"
        ]
        for selector: String in selectors {
            guard candidates.count < 4,
                  let text: String = self.firstText(in: element, selector: selector) else {
                continue
            }

            candidates.append("\(selector)=\(self.shortPreview(text, limit: 60))")
        }

        return candidates.isEmpty ? "nil" : candidates.joined(separator: ",")
    }

    private func firstText(in element: Element, selector: String) -> String? {
        guard let selectedElement: Element = try? element.select(selector).first() else {
            return nil
        }

        let text: String = ((try? selectedElement.text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func logEmptyListSelectorDiagnostics(
        in element: Element,
        source: Source,
        listRule: ListRule
    ) {
        RuleExecutionLogger.log(
            stage: .list,
            event: "item-selector-empty-diagnostics",
            fields: [
                "source": source.id,
                "listRule": listRule.id ?? "nil",
                "selector": listRule.item,
                "topClasses": self.topClassSummary(in: element).joined(separator: "|"),
                "linkSamples": self.listLinkSamples(in: element).joined(separator: "|")
            ]
        )
    }

    private func topClassSummary(in element: Element) -> [String] {
        let elementsWithClass: [Element] = (try? element.select("[class]").array()) ?? []
        var countsByClass: [String: Int] = [:]

        for selectedElement: Element in elementsWithClass {
            let rawClassName: String = (try? selectedElement.className()) ?? ""
            let classNames: [String] = rawClassName
                .split(separator: " ")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }

            for className: String in classNames {
                countsByClass[className, default: 0] += 1
            }
        }

        return countsByClass
            .sorted { left, right in
                if left.value == right.value {
                    return left.key < right.key
                }
                return left.value > right.value
            }
            .prefix(16)
            .map { className, count in
                return "\(className):\(count)"
            }
    }

    private func listLinkSamples(in element: Element) -> [String] {
        let links: [Element] = (try? element.select("a[href]").array()) ?? []
        let detailSignals: [String] = [
            "/manga/",
            "/comic/",
            "/comics/",
            "/info/",
            "/series/",
            "/title/"
        ]
        var samples: [String] = []
        var seen: Set<String> = Set<String>()

        for link: Element in links {
            guard samples.count < 8 else {
                break
            }

            let href: String = ((try? link.attr("href")) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard href.isEmpty == false,
                  href.hasPrefix("#") == false,
                  detailSignals.contains(where: { signal in href.localizedCaseInsensitiveContains(signal) }) else {
                continue
            }

            let title: String = ((try? link.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let sample: String = title.isEmpty
                ? href
                : "\(self.shortPreview(title, limit: 40))=>\(href)"

            guard seen.contains(sample) == false else {
                continue
            }

            seen.insert(sample)
            samples.append(sample)
        }

        if samples.isEmpty {
            for link: Element in links {
                guard samples.count < 8 else {
                    break
                }

                let href: String = ((try? link.attr("href")) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let title: String = ((try? link.text()) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard href.isEmpty == false,
                      href.hasPrefix("#") == false,
                      title.isEmpty == false else {
                    continue
                }

                let sample: String = "\(self.shortPreview(title, limit: 40))=>\(href)"
                guard seen.contains(sample) == false else {
                    continue
                }

                seen.insert(sample)
                samples.append(sample)
            }
        }

        return samples
    }

    private func topLevelSelectorParts(_ selector: String) -> [String] {
        var parts: [String] = []
        var current: String = ""
        var parenthesisDepth: Int = 0
        var bracketDepth: Int = 0
        var quote: Character?
        var previousCharacter: Character?

        for character: Character in selector {
            if let activeQuote: Character = quote {
                current.append(character)

                if character == activeQuote && previousCharacter != "\\" {
                    quote = nil
                }

                previousCharacter = character
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
                current.append(character)
            case "(":
                parenthesisDepth += 1
                current.append(character)
            case ")":
                parenthesisDepth = max(0, parenthesisDepth - 1)
                current.append(character)
            case "[":
                bracketDepth += 1
                current.append(character)
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
                current.append(character)
            case "," where parenthesisDepth == 0 && bracketDepth == 0:
                let part: String = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if part.isEmpty == false {
                    parts.append(part)
                }
                current = ""
            default:
                current.append(character)
            }

            previousCharacter = character
        }

        let finalPart: String = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalPart.isEmpty == false {
            parts.append(finalPart)
        }

        return parts
    }

    private func filteredElements(
        _ elements: [Element],
        excluding excludeRules: [ExtractRule],
        in scope: Element
    ) throws -> [Element] {
        guard excludeRules.isEmpty == false else {
            return elements
        }

        var excludedHTML: Set<String> = Set<String>()

        for excludeRule: ExtractRule in excludeRules {
            for element: Element in try self.selectedElements(element: scope, rule: excludeRule) {
                excludedHTML.insert(try element.outerHtml())
            }
        }

        return try elements.filter { element in
            return excludedHTML.contains(try element.outerHtml()) == false
        }
    }

    /// 中文注释：按 ExtractRule 从当前节点抽取字符串。旧规则使用 function，V2 规则可使用 functions 串联转换。
    private func extract(element: Element, rule: ExtractRule) throws -> String {
        let selectedElement: Element? = try self.selectedElements(element: element, rule: rule).first
        let rawValue: String = try self.rawExtractValue(
            selectedElement: selectedElement,
            rule: rule
        )

        let transformedValue: String = try self.applyLegacyRegexIfNeeded(
            to: rawValue,
            rule: rule
        )

        if self.isEffectivelyEmpty(transformedValue),
           let fallbackRules: [ExtractRule] = rule.fallback {
            for fallbackRule: ExtractRule in fallbackRules {
                let fallbackValue: String = try self.extract(element: element, rule: fallbackRule)

                if self.isEffectivelyEmpty(fallbackValue) == false {
                    return fallbackValue
                }
            }
        }

        return transformedValue
    }

    /// 中文注释：执行单步或多步抽取。functions 存在时按数组顺序处理，不存在时保持旧版 function 行为。
    private func rawExtractValue(selectedElement: Element?, rule: ExtractRule) throws -> String {
        guard let functions: [ExtractFunction] = rule.functions,
              functions.isEmpty == false else {
            return try self.applyExtractFunction(
                rule.function,
                selectedElement: selectedElement,
                currentValue: "",
                rule: rule
            )
        }

        var currentValue: String = ""

        for function: ExtractFunction in functions {
            currentValue = try self.applyExtractFunction(
                function,
                selectedElement: selectedElement,
                currentValue: currentValue,
                rule: rule
            )
        }

        return currentValue
    }

    /// 中文注释：source 类函数从 DOM 取值，transform 类函数只处理上一步字符串结果。
    private func applyExtractFunction(
        _ function: ExtractFunction,
        selectedElement: Element?,
        currentValue: String,
        rule: ExtractRule
    ) throws -> String {
        switch function {
        case .text:
            return try selectedElement?.text() ?? ""
        case .html:
            return try selectedElement?.html() ?? ""
        case .attr:
            return try self.extractAttribute(
                element: selectedElement,
                attributeExpression: rule.param ?? ""
            )
        case .raw:
            return try selectedElement?.outerHtml() ?? ""
        case .url:
            return try self.extractAttribute(
                element: selectedElement,
                attributeExpression: rule.param ?? "href"
            )
        case .decodeBase64:
            return self.decodeBase64(currentValue)
        case .removingPercentEncoding:
            return currentValue.removingPercentEncoding ?? currentValue
        case .addingPercentEncoding:
            return currentValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? currentValue
        case .reversed:
            return String(currentValue.reversed())
        case .regexReplacement:
            return try self.applyRegexReplacement(to: currentValue, rule: rule)
        case .replace:
            return try self.applyReplace(to: currentValue, rule: rule)
        case .decompressFromBase64:
            return self.decompressZlibFromBase64(currentValue)
        }
    }

    private func decodeBase64(_ value: String) -> String {
        guard let data: Data = Data(base64Encoded: value),
              let decodedValue: String = String(data: data, encoding: .utf8) else {
            return ""
        }

        return decodedValue
    }

    /// 中文注释：decompressFromBase64 当前限定为 Base64 包裹的 zlib 数据，避免在没有算法字段时误猜其它压缩格式。
    private func decompressZlibFromBase64(_ value: String) -> String {
        guard let compressedData: Data = Data(base64Encoded: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return ""
        }

        let compressedBytes: [UInt8] = Array(compressedData)
        var outputSize: Int = max(compressedBytes.count * 4, 64)
        let maxOutputSize: Int = 1024 * 1024

        while outputSize <= maxOutputSize {
            var outputBytes: [UInt8] = Array(repeating: 0, count: outputSize)
            let decodedSize: Int = compressedBytes.withUnsafeBufferPointer { compressedBuffer in
                return outputBytes.withUnsafeMutableBufferPointer { outputBuffer in
                    guard let outputBaseAddress: UnsafeMutablePointer<UInt8> = outputBuffer.baseAddress,
                          let compressedBaseAddress: UnsafePointer<UInt8> = compressedBuffer.baseAddress else {
                        return 0
                    }

                    return compression_decode_buffer(
                        outputBaseAddress,
                        outputBuffer.count,
                        compressedBaseAddress,
                        compressedBuffer.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }

            if decodedSize > 0 {
                return String(data: Data(outputBytes.prefix(decodedSize)), encoding: .utf8) ?? ""
            }

            outputSize *= 2
        }

        return ""
    }

    /// 中文注释：replace 使用 param 表示被替换文本，replacement 表示替换后的文本，适合函数链里的轻量清洗。
    private func applyReplace(to value: String, rule: ExtractRule) throws -> String {
        guard let target: String = rule.param, target.isEmpty == false else {
            throw ExtractError.missingReplaceTarget
        }

        return value.replacingOccurrences(
            of: target,
            with: rule.replacement ?? ""
        )
    }

    private func applyRegexReplacement(to value: String, rule: ExtractRule) throws -> String {
        guard let regex: String = rule.regex, regex.isEmpty == false else {
            throw ExtractError.missingRegexReplacementPattern
        }

        return try self.applyRegex(
            to: value,
            regex: regex,
            replacement: rule.replacement
        )
    }

    private func applyLegacyRegexIfNeeded(to value: String, rule: ExtractRule) throws -> String {
        if rule.functions?.contains(.regexReplacement) == true {
            return value
        }

        return try self.applyRegex(
            to: value,
            regex: rule.regex,
            replacement: rule.replacement
        )
    }

    /// 中文注释：fallback 判定使用“实际可展示内容”而非字节长度，避免空白节点阻断备用规则。
    private func isEffectivelyEmpty(_ value: String) -> Bool {
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applyRegex(to value: String, regex: String?, replacement: String?) throws -> String {
        guard let regex: String = regex, regex.isEmpty == false else {
            return value
        }

        let regularExpression: NSRegularExpression = try NSRegularExpression(pattern: regex)
        let range: NSRange = NSRange(value.startIndex..<value.endIndex, in: value)

        if let replacement: String = replacement {
            return regularExpression.stringByReplacingMatches(
                in: value,
                range: range,
                withTemplate: replacement
            )
        }

        guard let match: NSTextCheckingResult = regularExpression.firstMatch(in: value, range: range),
              let matchRange: Range<String.Index> = Range(match.range(at: match.numberOfRanges > 1 ? 1 : 0), in: value) else {
            return ""
        }

        return String(value[matchRange])
    }

    private func extractRule(fromLegacyExpression expression: String) -> ExtractRule {
        if expression == "this" {
            return ExtractRule(
                selector: "this",
                function: .text,
                param: nil,
                regex: nil,
                replacement: nil,
                fallback: nil
            )
        }

        if let separatorIndex: String.Index = expression.lastIndex(of: "@") {
            let selector: String = String(expression[..<separatorIndex])
            let attributeExpression: String = String(expression[expression.index(after: separatorIndex)...])

            return ExtractRule(
                selector: selector.isEmpty ? "this" : selector,
                function: .attr,
                param: attributeExpression,
                regex: nil,
                replacement: nil,
                fallback: nil
            )
        }

        return ExtractRule(
            selector: expression,
            function: .text,
            param: nil,
            regex: nil,
            replacement: nil,
            fallback: nil
        )
    }

    private func extract(element: Element, expression: String) throws -> String {
        let expressions: [String] = self.legacyExpressionCandidates(from: expression)
        if expressions.count > 1 {
            var firstError: Error?
            var evaluatedCandidate: Bool = false

            for candidateExpression: String in expressions {
                do {
                    let value: String = try self.extractSingle(element: element, expression: candidateExpression)
                    evaluatedCandidate = true

                    if self.isEffectivelyEmpty(value) == false {
                        return value
                    }
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }

            if evaluatedCandidate {
                return ""
            }

            if let firstError: Error = firstError {
                throw firstError
            }

            return ""
        }

        return try self.extractSingle(element: element, expression: expressions.first ?? expression)
    }

    private func extractSingle(element: Element, expression: String) throws -> String {
        let normalizedExpression: String = self.normalizedCurrentElementAlias(expression)

        if normalizedExpression == "this" {
            return try element.text()
        }

        if let separatorIndex: String.Index = normalizedExpression.lastIndex(of: "@") {
            let selector: String = String(normalizedExpression[..<separatorIndex])
            let attributeExpression: String = String(normalizedExpression[normalizedExpression.index(after: separatorIndex)...])
            let selectedElements: [Element] = try self.selectedElements(element: element, selector: selector)

            for selectedElement: Element in selectedElements {
                let value: String = try self.extractAttribute(
                    element: selectedElement,
                    attributeExpression: attributeExpression
                )
                if self.isEffectivelyEmpty(value) == false {
                    return value
                }
            }

            return ""
        }

        let selectedElements: [Element] = try self.selectedElements(element: element, selector: normalizedExpression)
        for selectedElement: Element in selectedElements {
            let value: String = try selectedElement.text()
            if self.isEffectivelyEmpty(value) == false {
                return value
            }
        }

        return ""
    }

    private func legacyExpressionCandidates(from expression: String) -> [String] {
        let trimmedExpression: String = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let pipeExpressionParts: [String] = self.legacyPipeExpressionCandidates(from: trimmedExpression)
        if pipeExpressionParts.count > 1 {
            return pipeExpressionParts
        }

        let parts: [String] = trimmedExpression
            .split(separator: ",")
            .map { part in
                return String(part).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { $0.isEmpty == false }

        guard parts.count > 1 else {
            return [trimmedExpression]
        }

        // 中文注释：旧版站规常把候选抽取写成 "h3 a, img@alt" 或 "img@data-src, img@src"。
        // 中文注释：只要混入属性抽取，就逐个尝试，避免 lastIndex("@") 把整段 CSS group 拆坏。
        if parts.contains(where: { $0.contains("@") || $0 == "&" || $0 == "this" }) {
            return parts
        }

        // 中文注释：包含当前元素别名时无法作为 CSS group 直接交给 SwiftSoup。
        if parts.contains(where: { $0 == "&" || $0.hasPrefix("&@") }) {
            return parts
        }

        return [trimmedExpression]
    }

    private func legacyPipeExpressionCandidates(from expression: String) -> [String] {
        guard let firstAttributeSeparator: String.Index = expression.firstIndex(of: "@") else {
            return [expression]
        }

        let selector: String = String(expression[..<firstAttributeSeparator])
        let attributeExpression: String = String(expression[expression.index(after: firstAttributeSeparator)...])
        let parts: [String] = attributeExpression
            .split(separator: "|")
            .map { part in
                return String(part).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { $0.isEmpty == false }

        guard parts.count > 1,
              parts.contains(where: { $0.contains("@") }) else {
            return [expression]
        }

        return parts.map { part in
            if part.contains("@") {
                return part
            }

            return "\(selector)@\(part)"
        }
    }

    private func normalizedCurrentElementAlias(_ expression: String) -> String {
        let trimmedExpression: String = expression.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedExpression == "&" {
            return "this"
        }

        if trimmedExpression.hasPrefix("&@") {
            return "this" + trimmedExpression.dropFirst()
        }

        return trimmedExpression
    }

    /// 中文注释：selectedElement 方法封装当前类型的一段业务或界面行为。
    private func selectedElement(element: Element, selector: String) throws -> Element? {
        return try self.selectedElements(element: element, selector: selector).first
    }

    private func selectedElements(element: Element, selector: String) throws -> [Element] {
        if selector.isEmpty || selector == "this" || selector == "&" {
            return [element]
        }

        if selector == "parent" {
            return element.parent().map { [$0] } ?? []
        }

        if selector.hasPrefix("parent ") {
            let nestedSelector: String = String(selector.dropFirst("parent ".count))
            guard let parent: Element = element.parent() else {
                return []
            }

            return try parent.select(nestedSelector).array()
        }

        return try element.select(selector).array()
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
