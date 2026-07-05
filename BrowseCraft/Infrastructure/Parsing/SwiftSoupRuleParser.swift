import Compression
import Foundation
import SwiftSoup

// 中文注释：SwiftSoupRuleParser.swift 属于网页规则解析实现层，用于说明本文件承载的核心职责。

/// 中文注释：基于 SwiftSoup 的 HTML 规则解析器。
/// 中文注释：SwiftSoup 只出现在这里，应用其他部分都通过 RuleParsingService 使用解析能力。
final class SwiftSoupRuleParser: RuleParsingService, RuleListDebugParsingService, RulePaginationParsingService {
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
        let document: Document = try SwiftSoup.parse(html, source.baseURL)
        let elements: [Element] = try document.select(listRule.item).array()
        let items: [ContentItem] = try self.contentItems(
            from: elements,
            source: source,
            listRule: listRule,
            context: nil
        )

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

        let document: Document = try SwiftSoup.parse(html, source.baseURL)
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
                let elements: [Element] = try container.select(listRule.item).array()
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

    func debugParseList(
        html: String,
        source: Source,
        listRule: ListRule,
        context: ListContext?,
        sections: [SectionRule]?
    ) throws -> RuleListDebugParseResult {
        let document: Document = try SwiftSoup.parse(html, source.baseURL)
        var items: [ContentItem] = []
        var issues: [RuleDebugIssue] = []
        var seenItemIDs: Set<String> = Set<String>()
        var candidateCount: Int = 0

        if let sections: [SectionRule] = sections,
           sections.isEmpty == false {
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

                for (containerIndex, container) in containers.enumerated() {
                    let elements: [Element] = try container.select(listRule.item).array()
                    candidateCount += elements.count
                    let result: RuleListDebugParseResult = self.debugContentItems(
                        from: elements,
                        source: source,
                        listRule: listRule,
                        context: sectionContext,
                        issuePrefix: "section-\(section.id ?? String(containerIndex))"
                    )

                    for item: ContentItem in result.items where seenItemIDs.contains(item.id) == false {
                        seenItemIDs.insert(item.id)
                        items.append(item)
                    }

                    issues.append(contentsOf: result.issues)
                }
            }
        } else {
            let elements: [Element] = try document.select(listRule.item).array()
            candidateCount = elements.count
            let result: RuleListDebugParseResult = self.debugContentItems(
                from: elements,
                source: source,
                listRule: listRule,
                context: context,
                issuePrefix: "list"
            )
            items = result.items
            issues = result.issues
        }

        let logs: [RuleDebugExtractionLog] = self.debugListExtractionLogs(
            listRule: listRule,
            candidateCount: candidateCount,
            items: items
        )

        return RuleListDebugParseResult(
            items: items,
            extractionLogs: logs,
            issues: issues
        )
    }

    private func contentItems(
        from elements: [Element],
        source: Source,
        listRule: ListRule,
        context: ListContext?
    ) throws -> [ContentItem] {
        var items: [ContentItem] = []

        for element: Element in elements {
            let title: String = try self.extract(element: element, expression: listRule.title)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let link: String = try self.extract(element: element, expression: listRule.link)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // 中文注释：缺少标题或链接的列表项无法在应用中有效展示，直接跳过。
            if title.isEmpty || link.isEmpty {
                continue
            }

            let detailURL: String = self.urlResolver.absoluteString(link, baseURLString: source.baseURL)
            let coverURL: String? = try self.optionalExtract(
                element: element,
                expression: listRule.cover,
                baseURLString: source.baseURL
            )
            let latestText: String? = try self.optionalExtract(
                element: element,
                expression: listRule.latestText,
                baseURLString: nil
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

        return items
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

    private func debugContentItems(
        from elements: [Element],
        source: Source,
        listRule: ListRule,
        context: ListContext?,
        issuePrefix: String
    ) -> RuleListDebugParseResult {
        var items: [ContentItem] = []
        var issues: [RuleDebugIssue] = []

        for (index, element) in elements.enumerated() {
            let title: String = self.debugExtract(
                element: element,
                expression: listRule.title,
                ruleID: listRule.id,
                field: .title,
                index: index,
                issuePrefix: issuePrefix,
                issues: &issues
            )
            let link: String = self.debugExtract(
                element: element,
                expression: listRule.link,
                ruleID: listRule.id,
                field: .link,
                index: index,
                issuePrefix: issuePrefix,
                issues: &issues
            )

            if title.isEmpty {
                issues.append(
                    self.debugIssue(
                        id: "\(issuePrefix)-\(index)-title-empty",
                        ruleID: listRule.id,
                        field: .title,
                        category: .fieldMissing,
                        message: "Skipped list item \(index) because title was empty."
                    )
                )
            }

            if link.isEmpty {
                issues.append(
                    self.debugIssue(
                        id: "\(issuePrefix)-\(index)-link-empty",
                        ruleID: listRule.id,
                        field: .link,
                        category: .fieldMissing,
                        message: "Skipped list item \(index) because link was empty."
                    )
                )
            }

            if title.isEmpty || link.isEmpty {
                continue
            }

            let detailURL: String = self.urlResolver.absoluteString(link, baseURLString: source.baseURL)
            let coverURL: String? = self.debugOptionalExtract(
                element: element,
                expression: listRule.cover,
                baseURLString: source.baseURL,
                ruleID: listRule.id,
                field: .cover,
                index: index,
                issuePrefix: issuePrefix,
                issues: &issues
            )
            let latestText: String? = self.debugOptionalExtract(
                element: element,
                expression: listRule.latestText,
                baseURLString: nil,
                ruleID: listRule.id,
                field: .latestText,
                index: index,
                issuePrefix: issuePrefix,
                issues: &issues
            )

            items.append(
                ContentItem(
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
            )
        }

        return RuleListDebugParseResult(
            items: items,
            extractionLogs: [],
            issues: issues
        )
    }

    private func debugListExtractionLogs(
        listRule: ListRule,
        candidateCount: Int,
        items: [ContentItem]
    ) -> [RuleDebugExtractionLog] {
        return [
            RuleDebugExtractionLog(
                id: "list-\(listRule.id ?? "primary")-item",
                stage: .list,
                ruleID: listRule.id,
                selector: listRule.item,
                field: .item,
                candidateCount: candidateCount,
                outputCount: items.count,
                samples: Array(items.prefix(3).map(\.title)),
                message: "Selected list item candidates."
            ),
            RuleDebugExtractionLog(
                id: "list-\(listRule.id ?? "primary")-title",
                stage: .list,
                ruleID: listRule.id,
                selector: listRule.title,
                field: .title,
                candidateCount: candidateCount,
                outputCount: items.count,
                samples: Array(items.prefix(3).map(\.title)),
                message: "Extracted list item titles."
            ),
            RuleDebugExtractionLog(
                id: "list-\(listRule.id ?? "primary")-link",
                stage: .list,
                ruleID: listRule.id,
                selector: listRule.link,
                field: .link,
                candidateCount: candidateCount,
                outputCount: items.count,
                samples: Array(items.prefix(3).map(\.detailURL)),
                message: "Extracted list item detail links."
            ),
            RuleDebugExtractionLog(
                id: "list-\(listRule.id ?? "primary")-cover",
                stage: .list,
                ruleID: listRule.id,
                selector: listRule.cover,
                field: .cover,
                candidateCount: candidateCount,
                outputCount: items.filter { item in item.coverURL?.isEmpty == false }.count,
                samples: Array(items.compactMap(\.coverURL).prefix(3)),
                message: "Extracted list item covers."
            ),
            RuleDebugExtractionLog(
                id: "list-\(listRule.id ?? "primary")-latestText",
                stage: .list,
                ruleID: listRule.id,
                selector: listRule.latestText,
                field: .latestText,
                candidateCount: candidateCount,
                outputCount: items.filter { item in item.latestText?.isEmpty == false }.count,
                samples: Array(items.compactMap(\.latestText).prefix(3)),
                message: "Extracted list item latest text."
            )
        ]
    }

    private func debugExtract(
        element: Element,
        expression: String,
        ruleID: String?,
        field: RuleDebugField,
        index: Int,
        issuePrefix: String,
        issues: inout [RuleDebugIssue]
    ) -> String {
        do {
            return try self.extract(element: element, expression: expression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            issues.append(
                self.debugIssue(
                    id: "\(issuePrefix)-\(index)-\(field.rawValue)-error",
                    ruleID: ruleID,
                    field: field,
                    category: .parserError,
                    message: "Failed to extract \(field.rawValue) for list item \(index): \(error.localizedDescription)"
                )
            )
            return ""
        }
    }

    private func debugOptionalExtract(
        element: Element,
        expression: String?,
        baseURLString: String?,
        ruleID: String?,
        field: RuleDebugField,
        index: Int,
        issuePrefix: String,
        issues: inout [RuleDebugIssue]
    ) -> String? {
        guard let expression: String = expression else {
            return nil
        }

        do {
            return try self.optionalExtract(
                element: element,
                expression: expression,
                baseURLString: baseURLString
            )
        } catch {
            issues.append(
                self.debugIssue(
                    id: "\(issuePrefix)-\(index)-\(field.rawValue)-error",
                    ruleID: ruleID,
                    field: field,
                    category: .parserError,
                    message: "Failed to extract \(field.rawValue) for list item \(index): \(error.localizedDescription)"
                )
            )
            return nil
        }
    }

    private func debugIssue(
        id: String,
        ruleID: String?,
        field: RuleDebugField?,
        category: RuleDebugIssueCategory,
        message: String
    ) -> RuleDebugIssue {
        return RuleDebugIssue(
            id: id,
            severity: .warning,
            category: category,
            stage: .list,
            ruleID: ruleID,
            field: field,
            message: message
        )
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
        #if DEBUG
        let debugChapterSelector: String = "a[href*=\"/cn/chapters/\"]"
        let globalChapterLinkCount: Int = try document.select(debugChapterSelector).array().count
        #endif

        let scope: Element = try self.contextualScope(
            in: document,
            mainScopeRule: detailRule.mainScope,
            context: context
        ) ?? document

        #if DEBUG
        let scopeChapterLinkCount: Int = try scope.select(debugChapterSelector).array().count
        print(
            "[BrowseCraftRule] V2 chapter scope " +
            "mainScope=\(detailRule.mainScope?.selector ?? "nil") " +
            "contextSectionId=\(context?.sectionId ?? "nil") " +
            "contextSectionRole=\(context?.sectionRole?.rawValue ?? "nil") " +
            "scopeTag=\(scope.tagName()) " +
            "globalChapterLinkCount=\(globalChapterLinkCount) " +
            "scopeChapterLinkCount=\(scopeChapterLinkCount)"
        )
        #endif

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

        #if DEBUG
        print(
            "[BrowseCraftRule] V2 chapter containers " +
            "sectionContainer=\(chapterRule.section?.container.selector ?? "nil") " +
            "containerCount=\(containerScopes.count)"
        )

        for (index, containerScope) in containerScopes.enumerated() {
            let containerChapterLinks: [Element] = try containerScope.select(debugChapterSelector).array()
            print(
                "[BrowseCraftRule] V2 chapter container " +
                "index=\(index) " +
                "tag=\(containerScope.tagName()) " +
                "chapterLinkCount=\(containerChapterLinks.count)"
            )

            for previewElement: Element in containerChapterLinks.prefix(5) {
                print(
                    "[BrowseCraftRule] V2 chapter container preview " +
                    "index=\(index) " +
                    "title=\(try previewElement.text()) " +
                    "href=\(try previewElement.attr("href"))"
                )
            }
        }
        #endif

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

            for container: Element in containers {
                let scopedElements: [Element] = try container.select(chapterItemSelector).array()

                if scopedElements.isEmpty == false {
                    return scopedElements
                }
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
                    return compression_decode_buffer(
                        outputBuffer.baseAddress!,
                        outputBuffer.count,
                        compressedBuffer.baseAddress!,
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
            guard let parent: Element = element.parent() else {
                return nil
            }

            return try parent.select(nestedSelector).first()
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
