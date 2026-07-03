import Foundation
import SwiftSoup

// SwiftSoupRuleCandidateAnalyzer implements the P2-7.2 list candidate MVP.
// It recommends selectors with evidence only; it never mutates or saves a rule.

final class SwiftSoupRuleCandidateAnalyzer: RuleCandidateAnalyzingService {
    private struct ItemGroup {
        var selector: String
        var elements: [Element]
    }

    private struct FieldProbe {
        var field: RuleCandidateField
        var selector: String
        var function: ExtractFunction
        var param: String?
        var source: RuleCandidateSource
    }

    private let now: () -> Date
    private let idGenerator: () -> String

    init(
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = {
            return UUID().uuidString
        }
    ) {
        self.now = now
        self.idGenerator = idGenerator
    }

    func analyzeList(
        html: String,
        source: Source,
        listRule: ListRule?,
        pageID: String?,
        url: String?
    ) throws -> RuleCandidateReport {
        let document: Document = try SwiftSoup.parse(html, url ?? source.baseURL)
        let effectiveListRule: ListRule = listRule ?? source.rule.primaryListRule
        let itemGroups: [ItemGroup] = try self.itemGroups(in: document)
        let itemCandidates: [RuleCandidate] = try itemGroups.prefix(3).map { group in
            return try self.itemCandidate(
                group: group,
                stage: .list
            )
        }
        let bestItemGroup: ItemGroup? = itemGroups.first
        let fieldCandidates: [RuleCandidate]

        if let bestItemGroup: ItemGroup = bestItemGroup {
            fieldCandidates = try self.fieldCandidates(
                itemGroup: bestItemGroup,
                stage: .list
            )
        } else {
            fieldCandidates = []
        }

        let candidates: [RuleCandidate] = itemCandidates + fieldCandidates
        return RuleCandidateReport(
            id: self.idGenerator(),
            sourceID: source.id,
            sourceName: source.name,
            stage: .list,
            pageID: pageID,
            ruleID: effectiveListRule.id,
            url: url,
            generatedAt: self.now(),
            candidates: candidates,
            summary: self.summary(candidates: candidates)
        )
    }

    func analyzeDetail(
        html: String,
        source: Source,
        detailRule: DetailRule?,
        pageID: String?,
        url: String?
    ) throws -> RuleCandidateReport {
        let document: Document = try SwiftSoup.parse(html, url ?? source.baseURL)
        let effectiveDetailRule: DetailRule? = detailRule ?? source.rule.primaryDetailRule
        let chapterGroups: [ItemGroup] = try self.chapterItemGroups(in: document)
        let itemCandidates: [RuleCandidate] = try chapterGroups.prefix(3).map { group in
            return try self.chapterItemCandidate(
                group: group,
                stage: .detail
            )
        }
        let bestChapterGroup: ItemGroup? = chapterGroups.first
        let containerCandidate: RuleCandidate?
        let fieldCandidates: [RuleCandidate]

        if let bestChapterGroup: ItemGroup = bestChapterGroup {
            containerCandidate = try self.chapterContainerCandidate(
                group: bestChapterGroup,
                stage: .detail
            )
            fieldCandidates = try self.chapterFieldCandidates(
                itemGroup: bestChapterGroup,
                stage: .detail
            )
        } else {
            containerCandidate = nil
            fieldCandidates = []
        }

        let candidates: [RuleCandidate] = [containerCandidate].compactMap { candidate in
            return candidate
        } + itemCandidates + fieldCandidates
        return RuleCandidateReport(
            id: self.idGenerator(),
            sourceID: source.id,
            sourceName: source.name,
            stage: .detail,
            pageID: pageID,
            ruleID: effectiveDetailRule?.id,
            url: url,
            generatedAt: self.now(),
            candidates: candidates,
            summary: self.summary(candidates: candidates)
        )
    }

    func analyzeReader(
        html: String,
        source: Source,
        galleryRule: GalleryRule?,
        pageID: String?,
        url: String?
    ) throws -> RuleCandidateReport {
        let document: Document = try SwiftSoup.parse(html, url ?? source.baseURL)
        let effectiveGalleryRule: GalleryRule? = galleryRule ?? source.rule.primaryGalleryRule
        let imageGroups: [ItemGroup] = try self.imageGroups(in: document)
        let candidates: [RuleCandidate] = try imageGroups.prefix(3).map { group in
            return try self.imageCandidate(
                group: group,
                stage: .reader
            )
        }

        return RuleCandidateReport(
            id: self.idGenerator(),
            sourceID: source.id,
            sourceName: source.name,
            stage: .reader,
            pageID: pageID,
            ruleID: effectiveGalleryRule?.id,
            url: url,
            generatedAt: self.now(),
            candidates: candidates,
            summary: self.summary(candidates: candidates)
        )
    }

    func analyzePagination(
        html: String,
        source: Source,
        pagination: PaginationRule?,
        stage: RuleDebugStage,
        pageID: String?,
        ruleID: String?,
        currentURL: String?,
        urlTemplate: String?
    ) throws -> RuleCandidateReport {
        let document: Document = try SwiftSoup.parse(html, currentURL ?? source.baseURL)
        let nextPageCandidates: [RuleCandidate] = try self.nextPageLinkCandidates(
            in: document,
            stage: stage
        )
        let placeholderCandidate: RuleCandidate? = self.pagePlaceholderCandidate(
            pagination: pagination,
            stage: stage,
            currentURL: currentURL,
            urlTemplate: urlTemplate
        )
        let candidates: [RuleCandidate] = nextPageCandidates + [placeholderCandidate].compactMap { candidate in
            return candidate
        }

        return RuleCandidateReport(
            id: self.idGenerator(),
            sourceID: source.id,
            sourceName: source.name,
            stage: stage,
            pageID: pageID,
            ruleID: ruleID,
            url: currentURL,
            generatedAt: self.now(),
            candidates: candidates,
            summary: self.summary(candidates: candidates)
        )
    }

    private func itemGroups(in document: Document) throws -> [ItemGroup] {
        let allElements: [Element] = try document.select("main *, article, li, figure").array()
        var groupsBySelector: [String: [Element]] = [:]

        for element: Element in allElements {
            guard try self.isPotentialItemElement(element),
                  let selector: String = try self.selector(for: element) else {
                continue
            }

            groupsBySelector[selector, default: []].append(element)
        }

        let groups: [ItemGroup] = groupsBySelector.map { selector, elements in
            return ItemGroup(selector: selector, elements: elements)
        }

        return groups
            .filter { group in
                return group.elements.count >= 2 && group.elements.count <= 80
            }
            .sorted { lhs, rhs in
                let lhsScore: Double = (try? self.itemScore(group: lhs))?.value ?? 0
                let rhsScore: Double = (try? self.itemScore(group: rhs))?.value ?? 0
                if lhsScore == rhsScore {
                    return lhs.elements.count > rhs.elements.count
                }

                return lhsScore > rhsScore
            }
    }

    private func itemCandidate(group: ItemGroup, stage: RuleDebugStage) throws -> RuleCandidate {
        let score: RuleCandidateScore = try self.itemScore(group: group)
        return RuleCandidate(
            id: self.idGenerator(),
            field: .item,
            stage: stage,
            selector: group.selector,
            selectorKind: .css,
            function: .raw,
            param: nil,
            score: score,
            evidence: try self.evidence(
                elements: group.elements,
                sample: { element in
                    return try self.normalizedText(element)
                }
            ),
            warnings: try self.itemWarnings(group: group),
            source: .repeatedDOMStructure
        )
    }

    private func itemScore(group: ItemGroup) throws -> RuleCandidateScore {
        let elements: [Element] = group.elements
        let linkCount: Int = try elements.filter { element in
            return try element.select("a[href]").array().isEmpty == false
        }.count
        let imageCount: Int = try elements.filter { element in
            return try element.select("img[src], img[data-src]").array().isEmpty == false
        }.count
        let titleCount: Int = try elements.filter { element in
            return try self.firstNonEmptyText(in: element, selectors: ["a.title", ".title", "h1", "h2", "h3", "a"]).isEmpty == false
        }.count
        let linkRatio: Double = Double(linkCount) / Double(max(elements.count, 1))
        let imageRatio: Double = Double(imageCount) / Double(max(elements.count, 1))
        let titleRatio: Double = Double(titleCount) / Double(max(elements.count, 1))
        let countScore: Double = min(Double(elements.count) / 8, 1)
        let value: Double = (linkRatio * 0.35) + (titleRatio * 0.30) + (imageRatio * 0.20) + (countScore * 0.15)
        let confidence: RuleCandidateConfidence

        if value >= 0.75 {
            confidence = .high
        } else if value >= 0.45 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return RuleCandidateScore(
            value: value,
            confidence: confidence,
            reasons: [
                "matches=\(elements.count)",
                "linkRatio=\(self.formatted(linkRatio))",
                "titleRatio=\(self.formatted(titleRatio))",
                "imageRatio=\(self.formatted(imageRatio))"
            ]
        )
    }

    private func fieldCandidates(
        itemGroup: ItemGroup,
        stage: RuleDebugStage
    ) throws -> [RuleCandidate] {
        let probes: [FieldProbe] = [
            FieldProbe(field: .title, selector: "a.title", function: .text, param: nil, source: .semanticElement),
            FieldProbe(field: .title, selector: ".title", function: .text, param: nil, source: .semanticElement),
            FieldProbe(field: .title, selector: "h1, h2, h3", function: .text, param: nil, source: .semanticElement),
            FieldProbe(field: .title, selector: "a[href]", function: .text, param: nil, source: .semanticElement),
            FieldProbe(field: .link, selector: "a.title", function: .url, param: "href", source: .attributePattern),
            FieldProbe(field: .link, selector: "a[href]", function: .url, param: "href", source: .attributePattern),
            FieldProbe(field: .cover, selector: "img.cover", function: .attr, param: "data-src|src", source: .attributePattern),
            FieldProbe(field: .cover, selector: "img[data-src], img[src]", function: .attr, param: "data-src|src", source: .attributePattern),
            FieldProbe(field: .latestText, selector: ".badge", function: .text, param: nil, source: .semanticElement),
            FieldProbe(field: .latestText, selector: ".latest, .chapter, time", function: .text, param: nil, source: .semanticElement)
        ]
        var bestByField: [RuleCandidateField: RuleCandidate] = [:]

        for probe: FieldProbe in probes {
            guard let candidate: RuleCandidate = try self.fieldCandidate(
                probe: probe,
                elements: itemGroup.elements,
                stage: stage
            ) else {
                continue
            }

            if let existing: RuleCandidate = bestByField[probe.field],
               existing.score.value >= candidate.score.value {
                continue
            }

            bestByField[probe.field] = candidate
        }

        return [.title, .link, .cover, .latestText].compactMap { field in
            return bestByField[field]
        }
    }

    private func fieldCandidate(
        probe: FieldProbe,
        elements: [Element],
        stage: RuleDebugStage
    ) throws -> RuleCandidate? {
        var samples: [String] = []
        var matchedCount: Int = 0
        var sampleAttributes: [String: [String]] = [:]

        for element: Element in elements {
            guard let selectedElement: Element = try self.selectedFieldElement(
                in: element,
                selector: probe.selector
            ) else {
                continue
            }

            let value: String = try self.value(
                from: selectedElement,
                function: probe.function,
                param: probe.param
            )
            guard value.isEmpty == false else {
                continue
            }

            matchedCount += 1
            if samples.count < 5 {
                samples.append(value)
            }

            if let param: String = probe.param {
                sampleAttributes[param, default: []].append(value)
            }
        }

        guard matchedCount > 0 else {
            return nil
        }

        let ratio: Double = Double(matchedCount) / Double(max(elements.count, 1))
        let confidence: RuleCandidateConfidence

        if ratio >= 0.8 {
            confidence = .high
        } else if ratio >= 0.5 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return RuleCandidate(
            id: self.idGenerator(),
            field: probe.field,
            stage: stage,
            selector: probe.selector,
            selectorKind: .css,
            function: probe.function,
            param: probe.param,
            score: RuleCandidateScore(
                value: ratio,
                confidence: confidence,
                reasons: [
                    "matched=\(matchedCount)",
                    "items=\(elements.count)",
                    "ratio=\(self.formatted(ratio))"
                ]
            ),
            evidence: RuleCandidateEvidence(
                candidateCount: elements.count,
                matchedCount: matchedCount,
                sampleValues: samples,
                sampleAttributes: sampleAttributes,
                ancestorHints: []
            ),
            warnings: self.fieldWarnings(
                field: probe.field,
                matchedCount: matchedCount,
                totalCount: elements.count
            ),
            source: probe.source
        )
    }

    private func chapterItemGroups(in document: Document) throws -> [ItemGroup] {
        let links: [Element] = try document.select("main a[href], article a[href], section a[href], div a[href], li a[href]").array()
        var groupsBySelector: [String: [Element]] = [:]
        var seenHTML: Set<String> = Set<String>()

        for link: Element in links {
            guard try self.isPotentialChapterLink(link),
                  let itemElement: Element = try self.chapterItemElement(for: link),
                  let selector: String = try self.selector(for: itemElement) else {
                continue
            }

            let html: String = try itemElement.outerHtml()
            guard seenHTML.contains(html) == false else {
                continue
            }

            seenHTML.insert(html)
            groupsBySelector[selector, default: []].append(itemElement)
        }

        let groups: [ItemGroup] = groupsBySelector.map { selector, elements in
            return ItemGroup(selector: selector, elements: elements)
        }

        return groups
            .filter { group in
                return group.elements.count >= 2 && group.elements.count <= 200
            }
            .sorted { lhs, rhs in
                let lhsScore: Double = (try? self.chapterItemScore(group: lhs))?.value ?? 0
                let rhsScore: Double = (try? self.chapterItemScore(group: rhs))?.value ?? 0
                if lhsScore == rhsScore {
                    return lhs.elements.count > rhs.elements.count
                }

                return lhsScore > rhsScore
            }
    }

    private func chapterContainerCandidate(group: ItemGroup, stage: RuleDebugStage) throws -> RuleCandidate? {
        guard let container: Element = try self.commonContainer(for: group),
              let selector: String = try self.containerSelector(for: container) else {
            return nil
        }

        let matchedCount: Int = try container.select(group.selector).array().count
        let ratio: Double = Double(min(matchedCount, group.elements.count)) / Double(max(group.elements.count, 1))

        return RuleCandidate(
            id: self.idGenerator(),
            field: .chapterContainer,
            stage: stage,
            selector: selector,
            selectorKind: .css,
            function: .raw,
            param: nil,
            score: RuleCandidateScore(
                value: ratio,
                confidence: ratio >= 0.8 ? .high : .medium,
                reasons: [
                    "chapterItems=\(group.elements.count)",
                    "containerMatches=\(matchedCount)",
                    "itemSelector=\(group.selector)"
                ]
            ),
            evidence: RuleCandidateEvidence(
                candidateCount: 1,
                matchedCount: matchedCount,
                sampleValues: try group.elements.prefix(5).map { element in
                    return try self.normalizedText(element)
                },
                sampleAttributes: [:],
                ancestorHints: try self.ancestorHints(for: container)
            ),
            warnings: [],
            source: .repeatedDOMStructure
        )
    }

    private func chapterItemCandidate(group: ItemGroup, stage: RuleDebugStage) throws -> RuleCandidate {
        return RuleCandidate(
            id: self.idGenerator(),
            field: .chapterItem,
            stage: stage,
            selector: group.selector,
            selectorKind: .css,
            function: .raw,
            param: nil,
            score: try self.chapterItemScore(group: group),
            evidence: try self.evidence(
                elements: group.elements,
                sample: { element in
                    return try self.normalizedText(element)
                }
            ),
            warnings: try self.chapterItemWarnings(group: group),
            source: .repeatedDOMStructure
        )
    }

    private func chapterItemScore(group: ItemGroup) throws -> RuleCandidateScore {
        let elements: [Element] = group.elements
        let linkCount: Int = try elements.filter { element in
            return try self.selectedFieldElement(in: element, selector: "a[href]") != nil
        }.count
        let chapterTextCount: Int = try elements.filter { element in
            return try self.looksLikeChapterText(self.normalizedText(element))
        }.count
        let linkRatio: Double = Double(linkCount) / Double(max(elements.count, 1))
        let textRatio: Double = Double(chapterTextCount) / Double(max(elements.count, 1))
        let countScore: Double = min(Double(elements.count) / 12, 1)
        let value: Double = (linkRatio * 0.45) + (textRatio * 0.35) + (countScore * 0.20)
        let confidence: RuleCandidateConfidence

        if value >= 0.75 {
            confidence = .high
        } else if value >= 0.45 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return RuleCandidateScore(
            value: value,
            confidence: confidence,
            reasons: [
                "matches=\(elements.count)",
                "linkRatio=\(self.formatted(linkRatio))",
                "chapterTextRatio=\(self.formatted(textRatio))"
            ]
        )
    }

    private func chapterFieldCandidates(
        itemGroup: ItemGroup,
        stage: RuleDebugStage
    ) throws -> [RuleCandidate] {
        let probes: [FieldProbe] = [
            FieldProbe(field: .chapterTitle, selector: "a[href]", function: .text, param: nil, source: .semanticElement),
            FieldProbe(field: .chapterTitle, selector: ".title", function: .text, param: nil, source: .semanticElement),
            FieldProbe(field: .chapterLink, selector: "a[href]", function: .url, param: "href", source: .attributePattern)
        ]
        var bestByField: [RuleCandidateField: RuleCandidate] = [:]

        for probe: FieldProbe in probes {
            guard let candidate: RuleCandidate = try self.fieldCandidate(
                probe: probe,
                elements: itemGroup.elements,
                stage: stage
            ) else {
                continue
            }

            if let existing: RuleCandidate = bestByField[probe.field],
               existing.score.value >= candidate.score.value {
                continue
            }

            bestByField[probe.field] = candidate
        }

        return [.chapterTitle, .chapterLink].compactMap { field in
            return bestByField[field]
        }
    }

    private func imageGroups(in document: Document) throws -> [ItemGroup] {
        let images: [Element] = try document.select("main img, article img, section img, div img, picture img").array()
        var groupsBySelector: [String: [Element]] = [:]
        var seenHTML: Set<String> = Set<String>()

        for image: Element in images {
            guard try self.isPotentialReaderImage(image),
                  let selector: String = try self.imageSelector(for: image) else {
                continue
            }

            let html: String = try image.outerHtml()
            guard seenHTML.contains(html) == false else {
                continue
            }

            seenHTML.insert(html)
            groupsBySelector[selector, default: []].append(image)
        }

        let groups: [ItemGroup] = groupsBySelector.map { selector, elements in
            return ItemGroup(selector: selector, elements: elements)
        }

        return groups
            .filter { group in
                return group.elements.isEmpty == false && group.elements.count <= 300
            }
            .sorted { lhs, rhs in
                let lhsScore: Double = (try? self.imageScore(group: lhs))?.value ?? 0
                let rhsScore: Double = (try? self.imageScore(group: rhs))?.value ?? 0
                if lhsScore == rhsScore {
                    return lhs.elements.count > rhs.elements.count
                }

                return lhsScore > rhsScore
            }
    }

    private func imageCandidate(group: ItemGroup, stage: RuleDebugStage) throws -> RuleCandidate {
        let imageAttributeExpression: String = "data-src|data-original|data-lazy-src|src"
        return RuleCandidate(
            id: self.idGenerator(),
            field: .image,
            stage: stage,
            selector: group.selector,
            selectorKind: .css,
            function: .attr,
            param: imageAttributeExpression,
            score: try self.imageScore(group: group),
            evidence: RuleCandidateEvidence(
                candidateCount: group.elements.count,
                matchedCount: try group.elements.filter { element in
                    return try self.attributeValue(from: element, expression: imageAttributeExpression).isEmpty == false
                }.count,
                sampleValues: try group.elements.prefix(5).compactMap { element in
                    let value: String = try self.attributeValue(from: element, expression: imageAttributeExpression)
                    return value.isEmpty ? nil : value
                },
                sampleAttributes: [
                    imageAttributeExpression: try group.elements.prefix(5).compactMap { element in
                        let value: String = try self.attributeValue(from: element, expression: imageAttributeExpression)
                        return value.isEmpty ? nil : value
                    }
                ],
                ancestorHints: try self.ancestorHints(for: group.elements.first)
            ),
            warnings: try self.imageWarnings(group: group),
            source: .attributePattern
        )
    }

    private func imageScore(group: ItemGroup) throws -> RuleCandidateScore {
        let elements: [Element] = group.elements
        let readableImageCount: Int = try elements.filter { element in
            return try self.attributeValue(from: element, expression: "data-src|data-original|data-lazy-src|src").isEmpty == false
        }.count
        let contentHintCount: Int = try elements.filter { element in
            return try self.hasReaderImageHint(element)
        }.count
        let largeHintCount: Int = try elements.filter { element in
            return try self.hasLargeImageHint(element)
        }.count
        let readableRatio: Double = Double(readableImageCount) / Double(max(elements.count, 1))
        let contentHintRatio: Double = Double(contentHintCount) / Double(max(elements.count, 1))
        let largeHintRatio: Double = Double(largeHintCount) / Double(max(elements.count, 1))
        let countScore: Double = min(Double(elements.count) / 8, 1)
        let value: Double = (readableRatio * 0.40) + (contentHintRatio * 0.25) + (largeHintRatio * 0.20) + (countScore * 0.15)
        let confidence: RuleCandidateConfidence

        if value >= 0.75 {
            confidence = .high
        } else if value >= 0.45 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return RuleCandidateScore(
            value: value,
            confidence: confidence,
            reasons: [
                "matches=\(elements.count)",
                "imageURLRatio=\(self.formatted(readableRatio))",
                "contentHintRatio=\(self.formatted(contentHintRatio))",
                "largeHintRatio=\(self.formatted(largeHintRatio))"
            ]
        )
    }

    private func imageWarnings(group: ItemGroup) throws -> [RuleCandidateWarning] {
        var warnings: [RuleCandidateWarning] = []

        if group.elements.count < 2 {
            warnings.append(
                self.warning(
                    severity: .info,
                    category: .tooFewMatches,
                    message: "Reader image selector matched only \(group.elements.count) image."
                )
            )
        }

        let averageAltLength: Int = try group.elements.reduce(0) { total, element in
            let alt: String = try element.attr("alt")
            return total + alt.count
        } / max(group.elements.count, 1)

        if averageAltLength > 120 {
            warnings.append(
                self.warning(
                    severity: .warning,
                    category: .mixedContent,
                    message: "Reader image selector may include descriptive non-page images; average alt text is \(averageAltLength) characters."
                )
            )
        }

        return warnings
    }

    private func nextPageLinkCandidates(in document: Document, stage: RuleDebugStage) throws -> [RuleCandidate] {
        let links: [Element] = try document.select("a[href]").array()
        let candidates: [RuleCandidate] = try links.compactMap { link in
            guard try self.isPotentialNextPageLink(link),
                  let selector: String = try self.nextPageSelector(for: link) else {
                return nil
            }

            return try self.nextPageLinkCandidate(
                link: link,
                selector: selector,
                stage: stage
            )
        }

        var bestBySelector: [String: RuleCandidate] = [:]
        for candidate: RuleCandidate in candidates {
            if let existing: RuleCandidate = bestBySelector[candidate.selector],
               existing.score.value >= candidate.score.value {
                continue
            }

            bestBySelector[candidate.selector] = candidate
        }

        return bestBySelector.values
            .sorted { lhs, rhs in
                if lhs.score.value == rhs.score.value {
                    return lhs.selector < rhs.selector
                }

                return lhs.score.value > rhs.score.value
            }
            .prefix(3)
            .map { candidate in
                return candidate
            }
    }

    private func nextPageLinkCandidate(
        link: Element,
        selector: String,
        stage: RuleDebugStage
    ) throws -> RuleCandidate {
        let href: String = try link.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
        return RuleCandidate(
            id: self.idGenerator(),
            field: .nextPage,
            stage: stage,
            selector: selector,
            selectorKind: .css,
            function: .url,
            param: "href",
            score: try self.nextPageScore(link: link),
            evidence: RuleCandidateEvidence(
                candidateCount: 1,
                matchedCount: href.isEmpty ? 0 : 1,
                sampleValues: href.isEmpty ? [] : [href],
                sampleAttributes: href.isEmpty ? [:] : ["href": [href]],
                ancestorHints: try self.ancestorHints(for: link)
            ),
            warnings: [],
            source: .paginationLink
        )
    }

    private func pagePlaceholderCandidate(
        pagination: PaginationRule?,
        stage: RuleDebugStage,
        currentURL: String?,
        urlTemplate: String?
    ) -> RuleCandidate? {
        let explicitPlaceholder: String? = self.nonEmpty(pagination?.pagePlaceholder)
        let templatePlaceholder: String? = self.firstPagePlaceholder(in: urlTemplate)
        let currentURLPlaceholder: String? = self.pageParameterPlaceholder(in: currentURL)
        let placeholder: String? = explicitPlaceholder ?? templatePlaceholder ?? currentURLPlaceholder

        guard let placeholder: String = placeholder else {
            return nil
        }

        let selector: String = urlTemplate ?? currentURL ?? placeholder
        let placeholderSource: String = explicitPlaceholder != nil ? "rule" : templatePlaceholder != nil ? "template" : "url-parameter"
        let sampleValues: [String] = [urlTemplate, currentURL]
            .compactMap { value in
                return self.nonEmpty(value)
            }

        return RuleCandidate(
            id: self.idGenerator(),
            field: .nextPage,
            stage: stage,
            selector: selector,
            selectorKind: .current,
            function: .raw,
            param: placeholder,
            score: RuleCandidateScore(
                value: explicitPlaceholder != nil || templatePlaceholder != nil ? 0.85 : 0.60,
                confidence: explicitPlaceholder != nil || templatePlaceholder != nil ? .high : .medium,
                reasons: [
                    "pagePlaceholder=\(placeholder)",
                    "source=\(placeholderSource)"
                ]
            ),
            evidence: RuleCandidateEvidence(
                candidateCount: sampleValues.isEmpty ? 1 : sampleValues.count,
                matchedCount: 1,
                sampleValues: sampleValues.isEmpty ? [placeholder] : sampleValues,
                sampleAttributes: ["pagePlaceholder": [placeholder]],
                ancestorHints: []
            ),
            warnings: currentURLPlaceholder != nil && explicitPlaceholder == nil && templatePlaceholder == nil ? [
                self.warning(
                    severity: .info,
                    category: .unknown,
                    message: "Page placeholder inferred from current URL parameter; confirm the URL template before saving a rule."
                )
            ] : [],
            source: .manualSeed
        )
    }

    private func isPotentialNextPageLink(_ link: Element) throws -> Bool {
        if try self.isInsidePaginationNoiseContainer(link) {
            return false
        }

        let href: String = try link.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
        guard href.isEmpty == false,
              href.hasPrefix("#") == false,
              href.lowercased().hasPrefix("javascript:") == false else {
            return false
        }

        let marker: String = try self.nextPageMarker(for: link)
        if marker.contains("prev") || marker.contains("previous") || marker.contains("上一") || marker.contains("前へ") {
            return false
        }

        return self.nextPageHintScore(marker: marker, href: href) > 0
    }

    private func nextPageScore(link: Element) throws -> RuleCandidateScore {
        let href: String = try link.attr("href")
        let marker: String = try self.nextPageMarker(for: link)
        let hintScore: Double = self.nextPageHintScore(marker: marker, href: href)
        let confidence: RuleCandidateConfidence

        if hintScore >= 0.75 {
            confidence = .high
        } else if hintScore >= 0.45 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return RuleCandidateScore(
            value: hintScore,
            confidence: confidence,
            reasons: [
                "marker=\(marker)",
                "href=\(href)"
            ]
        )
    }

    private func nextPageHintScore(marker: String, href: String) -> Double {
        let normalizedHref: String = href.lowercased()
        var score: Double = 0

        if marker.contains("next") || marker.contains("下一") || marker.contains("下一页") || marker.contains("次へ") {
            score += 0.45
        }

        if marker.contains("rel=next") || marker.contains("aria=next") {
            score += 0.25
        }

        if normalizedHref.range(of: #"([?&](page|p)=\d+)|(/page/\d+)|(/p/\d+)"#, options: .regularExpression) != nil {
            score += 0.20
        }

        if marker.contains("disabled") || marker.contains("current") {
            score -= 0.25
        }

        return min(max(score, 0), 1)
    }

    private func nextPageMarker(for link: Element) throws -> String {
        let text: String = try self.normalizedText(link).lowercased()
        let className: String = try link.attr("class").lowercased()
        let id: String = try link.attr("id").lowercased()
        let rel: String = try link.attr("rel").lowercased()
        let ariaLabel: String = try link.attr("aria-label").lowercased()
        return "\(text) \(className) \(id) rel=\(rel) aria=\(ariaLabel)"
    }

    private func nextPageSelector(for link: Element) throws -> String? {
        let tagName: String = try link.tagName().lowercased()
        let classNames: [String] = try link.attr("class")
            .split(separator: " ")
            .map(String.init)
            .filter { className in
                return self.isUsefulClassName(className)
            }
        let usefulClasses: [String] = Array(classNames.prefix(2))

        if usefulClasses.isEmpty == false {
            return ([tagName] + usefulClasses.map { className in ".\(className)" }).joined()
        }

        if try link.attr("rel").lowercased() == "next" {
            return "a[rel=next]"
        }

        if try link.attr("aria-label").lowercased().contains("next") {
            return "a[aria-label*=next]"
        }

        return "a[href]"
    }

    private func firstPagePlaceholder(in template: String?) -> String? {
        guard let template: String = self.nonEmpty(template) else {
            return nil
        }

        if let range: Range<String.Index> = template.range(
            of: #"\{page[^}]*\}"#,
            options: .regularExpression
        ) {
            return String(template[range])
        }

        return nil
    }

    private func pageParameterPlaceholder(in url: String?) -> String? {
        guard let url: String = self.nonEmpty(url) else {
            return nil
        }

        if url.range(of: #"([?&])page=\d+"#, options: .regularExpression) != nil {
            return "page"
        }

        if url.range(of: #"([?&])p=\d+"#, options: .regularExpression) != nil {
            return "p"
        }

        return nil
    }

    private func isInsidePaginationNoiseContainer(_ element: Element) throws -> Bool {
        var currentElement: Element? = element

        while let current: Element = currentElement {
            let tagName: String = try current.tagName().lowercased()
            let id: String = try current.attr("id").lowercased()
            let className: String = try current.attr("class").lowercased()
            let marker: String = "\(tagName) \(id) \(className)"

            if ["header", "footer", "script", "style"].contains(tagName) {
                return true
            }

            if marker.contains("breadcrumb")
                || marker.contains("comment")
                || marker.contains("recommend")
                || marker.contains("related")
                || marker.contains("sidebar")
                || marker.contains("share") {
                return true
            }

            currentElement = try current.parent()
        }

        return false
    }

    private func chapterItemWarnings(group: ItemGroup) throws -> [RuleCandidateWarning] {
        var warnings: [RuleCandidateWarning] = try self.itemWarnings(group: group)
        let averageTextLength: Int = try self.averageTextLength(group.elements)

        if averageTextLength > 120 {
            warnings.append(
                self.warning(
                    severity: .warning,
                    category: .overbroadContainer,
                    message: "Chapter item selector may be too broad; average text is \(averageTextLength) characters."
                )
            )
        }

        return warnings
    }

    private func itemWarnings(group: ItemGroup) throws -> [RuleCandidateWarning] {
        var warnings: [RuleCandidateWarning] = []
        let averageTextLength: Int = try self.averageTextLength(group.elements)

        if averageTextLength > 300 {
            warnings.append(
                self.warning(
                    severity: .warning,
                    category: .overbroadContainer,
                    message: "Candidate item selector may be too broad; average text is \(averageTextLength) characters."
                )
            )
        }

        if group.selector.contains("nav") || group.selector.contains("footer") || group.selector.contains("header") {
            warnings.append(
                self.warning(
                    severity: .warning,
                    category: .navigationNoise,
                    message: "Candidate selector appears to come from navigation chrome."
                )
            )
        }

        if group.selector.contains("recommend") || group.selector.contains("related") || group.selector.contains("sidebar") {
            warnings.append(
                self.warning(
                    severity: .warning,
                    category: .recommendationNoise,
                    message: "Candidate selector appears to come from recommendation or sidebar content."
                )
            )
        }

        return warnings
    }

    private func fieldWarnings(
        field: RuleCandidateField,
        matchedCount: Int,
        totalCount: Int
    ) -> [RuleCandidateWarning] {
        guard matchedCount < totalCount else {
            return []
        }

        return [
            self.warning(
                severity: self.isRequiredField(field) ? .warning : .info,
                category: .missingRequiredField,
                message: "\(field.rawValue) matched \(matchedCount) of \(totalCount) candidate items."
            )
        ]
    }

    private func isRequiredField(_ field: RuleCandidateField) -> Bool {
        switch field {
        case .title, .link, .chapterTitle, .chapterLink, .image:
            return true
        case .section,
             .item,
             .cover,
             .latestText,
             .chapterContainer,
             .chapterItem,
             .nextPage,
             .unknown:
            return false
        }
    }

    private func selectedFieldElement(in element: Element, selector: String) throws -> Element? {
        if try element.iS(selector) {
            return element
        }

        return try element.select(selector).first()
    }

    private func isPotentialChapterLink(_ element: Element) throws -> Bool {
        if try self.isInsideDetailNoiseContainer(element) {
            return false
        }

        let text: String = try self.normalizedText(element)
        let href: String = try element.attr("href")

        guard text.isEmpty == false,
              href.isEmpty == false else {
            return false
        }

        return self.looksLikeChapterText(text) || self.looksLikeChapterURL(href)
    }

    private func isPotentialReaderImage(_ element: Element) throws -> Bool {
        if try self.isInsideReaderNoiseContainer(element) {
            return false
        }

        let source: String = try self.attributeValue(from: element, expression: "data-src|data-original|data-lazy-src|src")
        guard source.isEmpty == false,
              self.looksLikeImageURL(source),
              try self.looksLikeReaderNoiseImage(element) == false else {
            return false
        }

        return true
    }

    private func chapterItemElement(for link: Element) throws -> Element? {
        guard let parent: Element = try link.parent() else {
            return link
        }

        let parentTagName: String = try parent.tagName().lowercased()
        let parentLinkCount: Int = try parent.select("a[href]").array().count

        if ["li", "article", "div", "section"].contains(parentTagName),
           parentLinkCount <= 4,
           try self.isInsideDetailNoiseContainer(parent) == false {
            return parent
        }

        return link
    }

    private func looksLikeChapterText(_ text: String) -> Bool {
        let normalizedText: String = text.lowercased()
        let chapterPatterns: [String] = [
            "chapter",
            "episode",
            "ep.",
            "第",
            "话",
            "話",
            "回",
            "集"
        ]

        return chapterPatterns.contains { pattern in
            return normalizedText.contains(pattern)
        }
    }

    private func looksLikeChapterURL(_ href: String) -> Bool {
        let normalizedHref: String = href.lowercased()
        let urlPatterns: [String] = [
            "/chapter",
            "/chapters",
            "/reader",
            "/read",
            "/episode",
            "/episodes",
            "/ep"
        ]

        return urlPatterns.contains { pattern in
            return normalizedHref.contains(pattern)
        }
    }

    private func looksLikeImageURL(_ value: String) -> Bool {
        let normalizedValue: String = value.lowercased()
        let imageExtensions: [String] = [
            ".jpg",
            ".jpeg",
            ".png",
            ".webp",
            ".gif",
            ".avif"
        ]

        return imageExtensions.contains { imageExtension in
            return normalizedValue.contains(imageExtension)
        }
    }

    private func hasReaderImageHint(_ element: Element) throws -> Bool {
        let source: String = try self.attributeValue(from: element, expression: "data-src|data-original|data-lazy-src|src").lowercased()
        let className: String = try element.attr("class").lowercased()
        let id: String = try element.attr("id").lowercased()
        let alt: String = try element.attr("alt").lowercased()
        let marker: String = "\(source) \(className) \(id) \(alt)"
        let contentHints: [String] = [
            "page",
            "chapter",
            "comic",
            "manga",
            "reader",
            "webcomic",
            "episode",
            "scan"
        ]

        return contentHints.contains { hint in
            return marker.contains(hint)
        }
    }

    private func hasLargeImageHint(_ element: Element) throws -> Bool {
        let width: Int = Int(try element.attr("width")) ?? 0
        let height: Int = Int(try element.attr("height")) ?? 0

        if width >= 500 || height >= 500 {
            return true
        }

        let source: String = try self.attributeValue(from: element, expression: "data-src|data-original|data-lazy-src|src").lowercased()
        return source.contains("/large/")
            || source.contains("/origin/")
            || source.contains("/original/")
            || source.contains("/pages/")
    }

    private func looksLikeReaderNoiseImage(_ element: Element) throws -> Bool {
        let source: String = try self.attributeValue(from: element, expression: "data-src|data-original|data-lazy-src|src").lowercased()
        let className: String = try element.attr("class").lowercased()
        let id: String = try element.attr("id").lowercased()
        let alt: String = try element.attr("alt").lowercased()
        let marker: String = "\(source) \(className) \(id) \(alt)"
        let noiseHints: [String] = [
            "advert",
            "avatar",
            "banner",
            "button",
            "icon",
            "logo",
            "promo",
            "qrcode",
            "sponsor",
            "sprite",
            "thumb"
        ]

        if self.containsToken("ad", in: marker) || self.containsToken("ads", in: marker) {
            return true
        }

        return noiseHints.contains { hint in
            return marker.contains(hint)
        }
    }

    private func isInsideDetailNoiseContainer(_ element: Element) throws -> Bool {
        var currentElement: Element? = element

        while let current: Element = currentElement {
            let tagName: String = try current.tagName().lowercased()
            let idValue: String = try current.attr("id")
            let classValue: String = try current.attr("class")
            let id: String = idValue.lowercased()
            let className: String = classValue.lowercased()
            let marker: String = "\(tagName) \(id) \(className)"

            if ["nav", "header", "footer", "script", "style"].contains(tagName) {
                return true
            }

            if marker.contains("recommend")
                || marker.contains("related")
                || marker.contains("sidebar")
                || marker.contains("language")
                || marker.contains("locale")
                || marker.contains("breadcrumb") {
                return true
            }

            currentElement = try current.parent()
        }

        return false
    }

    private func isInsideReaderNoiseContainer(_ element: Element) throws -> Bool {
        var currentElement: Element? = element

        while let current: Element = currentElement {
            let tagName: String = try current.tagName().lowercased()
            let idValue: String = try current.attr("id")
            let classValue: String = try current.attr("class")
            let id: String = idValue.lowercased()
            let className: String = classValue.lowercased()
            let marker: String = "\(tagName) \(id) \(className)"

            if ["nav", "header", "footer", "script", "style"].contains(tagName) {
                return true
            }

            if self.containsToken("ad", in: marker)
                || self.containsToken("ads", in: marker)
                || marker.contains("advert")
                || marker.contains("avatar")
                || marker.contains("banner")
                || marker.contains("comment")
                || marker.contains("logo")
                || marker.contains("recommend")
                || marker.contains("related")
                || marker.contains("sidebar")
                || marker.contains("share")
                || marker.contains("sponsor") {
                return true
            }

            currentElement = try current.parent()
        }

        return false
    }

    private func containsToken(_ token: String, in marker: String) -> Bool {
        return marker.range(
            of: "(^|[^a-z0-9])\(NSRegularExpression.escapedPattern(for: token))($|[^a-z0-9])",
            options: .regularExpression
        ) != nil
    }

    private func commonContainer(for group: ItemGroup) throws -> Element? {
        guard let firstElement: Element = group.elements.first else {
            return nil
        }

        var currentElement: Element? = try firstElement.parent()

        while let current: Element = currentElement {
            if try self.isInsideDetailNoiseContainer(current) {
                return nil
            }

            let matchCount: Int = try current.select(group.selector).array().count
            if matchCount >= group.elements.count {
                return current
            }

            currentElement = try current.parent()
        }

        return try firstElement.parent()
    }

    private func containerSelector(for element: Element) throws -> String? {
        let tagName: String = try element.tagName().lowercased()
        let classNames: [String] = try element.attr("class")
            .split(separator: " ")
            .map(String.init)
            .filter { className in
                return self.isUsefulClassName(className)
            }
        let usefulClasses: [String] = Array(classNames.prefix(2))

        if usefulClasses.isEmpty == false {
            return ([tagName] + usefulClasses.map { className in ".\(className)" }).joined()
        }

        if let id: String = try? element.attr("id"),
           id.isEmpty == false,
           self.isUsefulClassName(id) {
            return "\(tagName)#\(id)"
        }

        if ["main", "section", "div", "ul", "ol", "article"].contains(tagName) {
            return tagName
        }

        return nil
    }

    private func imageSelector(for element: Element) throws -> String? {
        let tagName: String = try element.tagName().lowercased()
        guard tagName == "img" else {
            return nil
        }

        let classNames: [String] = try element.attr("class")
            .split(separator: " ")
            .map(String.init)
            .filter { className in
                return self.isUsefulImageClassName(className)
            }
        let usefulClasses: [String] = Array(classNames.prefix(2))

        if usefulClasses.isEmpty == false {
            return ([tagName] + usefulClasses.map { className in ".\(className)" }).joined()
        }

        if try element.hasAttr("data-src") {
            return "img[data-src]"
        }

        if try element.hasAttr("data-original") {
            return "img[data-original]"
        }

        if try element.hasAttr("data-lazy-src") {
            return "img[data-lazy-src]"
        }

        if try element.hasAttr("src") {
            return "img[src]"
        }

        return nil
    }

    private func isUsefulImageClassName(_ className: String) -> Bool {
        let normalizedClassName: String = className.lowercased()
        let ignoredClassNames: Set<String> = [
            "active",
            "content",
            "hidden",
            "image",
            "img",
            "item",
            "lazy",
            "lazyload",
            "selected",
            "show"
        ]

        guard ignoredClassNames.contains(normalizedClassName) == false else {
            return false
        }

        return self.isUsefulClassName(className)
    }

    private func isPotentialItemElement(_ element: Element) throws -> Bool {
        let tagName: String = try element.tagName().lowercased()
        guard ["article", "li", "figure", "div", "section", "a"].contains(tagName) else {
            return false
        }

        if try self.isInsideNoiseContainer(element) {
            return false
        }

        let text: String = try self.normalizedText(element)
        let href: String = try element.attr("href")
        let hasLink: Bool = try element.select("a[href]").array().isEmpty == false || (tagName == "a" && href.isEmpty == false)
        let hasImage: Bool = try element.select("img[src], img[data-src]").array().isEmpty == false
        return text.isEmpty == false && (hasLink || hasImage)
    }

    private func isInsideNoiseContainer(_ element: Element) throws -> Bool {
        var currentElement: Element? = element

        while let current: Element = currentElement {
            let tagName: String = try current.tagName().lowercased()
            if ["nav", "header", "footer", "script", "style"].contains(tagName) {
                return true
            }

            currentElement = try current.parent()
        }

        return false
    }

    private func selector(for element: Element) throws -> String? {
        let tagName: String = try element.tagName().lowercased()
        let classNames: [String] = try element.attr("class")
            .split(separator: " ")
            .map(String.init)
            .filter { className in
                return self.isUsefulClassName(className)
            }
        let usefulClasses: [String] = Array(classNames.prefix(2))

        if usefulClasses.isEmpty == false {
            return ([tagName] + usefulClasses.map { className in ".\(className)" }).joined()
        }

        if ["article", "li", "figure"].contains(tagName) {
            return tagName
        }

        return nil
    }

    private func isUsefulClassName(_ className: String) -> Bool {
        let normalizedClassName: String = className.lowercased()
        let ignoredClassNames: Set<String> = [
            "active",
            "container",
            "content",
            "flex",
            "grid",
            "hidden",
            "item",
            "row",
            "selected",
            "show",
            "wrapper"
        ]

        guard ignoredClassNames.contains(normalizedClassName) == false else {
            return false
        }

        return normalizedClassName.range(of: #"^[a-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    private func evidence(
        elements: [Element],
        sample: (Element) throws -> String
    ) throws -> RuleCandidateEvidence {
        let sampleValues: [String] = try elements.prefix(5).compactMap { element in
            let value: String = try sample(element)
            return value.isEmpty ? nil : value
        }

        return RuleCandidateEvidence(
            candidateCount: elements.count,
            matchedCount: elements.count,
            sampleValues: sampleValues,
            sampleAttributes: [:],
            ancestorHints: try self.ancestorHints(for: elements.first)
        )
    }

    private func ancestorHints(for element: Element?) throws -> [String] {
        var hints: [String] = []
        var currentElement: Element? = try element?.parent()

        while let current: Element = currentElement, hints.count < 3 {
            let tagName: String = try current.tagName().lowercased()
            let id: String = try current.attr("id")
            let className: String = try current.attr("class")
            var hint: String = tagName

            if id.isEmpty == false {
                hint += "#\(id)"
            } else if className.isEmpty == false {
                hint += ".\(className.split(separator: " ").prefix(2).joined(separator: "."))"
            }

            hints.append(hint)
            currentElement = try current.parent()
        }

        return hints
    }

    private func firstNonEmptyText(in element: Element, selectors: [String]) throws -> String {
        for selector: String in selectors {
            guard let selectedElement: Element = try element.select(selector).first() else {
                continue
            }

            let text: String = try self.normalizedText(selectedElement)
            if text.isEmpty == false {
                return text
            }
        }

        return ""
    }

    private func value(from element: Element, function: ExtractFunction, param: String?) throws -> String {
        switch function {
        case .text:
            return try self.normalizedText(element)
        case .url:
            return try self.attributeValue(from: element, expression: param ?? "href")
        case .attr:
            return try self.attributeValue(from: element, expression: param ?? "")
        case .html:
            return try element.html().trimmingCharacters(in: .whitespacesAndNewlines)
        case .raw:
            return try element.outerHtml().trimmingCharacters(in: .whitespacesAndNewlines)
        case .decodeBase64,
             .removingPercentEncoding,
             .addingPercentEncoding,
             .replace,
             .decompressFromBase64,
             .reversed,
             .regexReplacement:
            return try self.normalizedText(element)
        }
    }

    private func attributeValue(from element: Element, expression: String) throws -> String {
        for attribute: String in expression.split(separator: "|").map(String.init) {
            let value: String = try element.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty == false {
                return value
            }
        }

        return ""
    }

    private func normalizedText(_ element: Element) throws -> String {
        return try element.text()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func averageTextLength(_ elements: [Element]) throws -> Int {
        guard elements.isEmpty == false else {
            return 0
        }

        let totalLength: Int = try elements.reduce(0) { total, element in
            let text: String = try self.normalizedText(element)
            return total + text.count
        }

        return totalLength / elements.count
    }

    private func summary(candidates: [RuleCandidate]) -> RuleCandidateSummary {
        return RuleCandidateSummary(
            candidateCount: candidates.count,
            highConfidenceCount: candidates.filter { candidate in
                return candidate.score.confidence == .high
            }.count,
            warningCount: candidates.reduce(0) { count, candidate in
                return count + candidate.warnings.count
            },
            coveredFields: Array(Set(candidates.map(\.field))).sorted { lhs, rhs in
                return lhs.rawValue < rhs.rawValue
            }
        )
    }

    private func warning(
        severity: RuleCandidateWarningSeverity,
        category: RuleCandidateWarningCategory,
        message: String
    ) -> RuleCandidateWarning {
        return RuleCandidateWarning(
            id: self.idGenerator(),
            severity: severity,
            category: category,
            message: message
        )
    }

    private func formatted(_ value: Double) -> String {
        return String(format: "%.2f", value)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmedValue: String = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmedValue.isEmpty == false else {
            return nil
        }

        return trimmedValue
    }
}
