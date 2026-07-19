import Foundation
import SwiftSoup

// 中文注释：Video V2 的 CSS/DOM 实现物理隔离在 Infrastructure；上层只依赖 VideoRuleSourceParsingService。
final class SwiftSoupVideoRuleSourceParser: VideoRuleSourceParsingService {
    func parseList(
        html: String,
        pageURL: URL,
        rule: VideoListRule
    ) throws -> VideoRuleParsedList {
        guard rule.effectiveSourceStrategy.usesDOM,
              let itemRule: ExtractRule = rule.item,
              let fields: VideoListFields = rule.fields else {
            throw VideoRuleSourceParsingError.incompleteDOMRule(kind: "list", ruleID: rule.id)
        }
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

        let candidates: [Element] = try self.selectedElements(from: document, rule: itemRule)
        var items: [VideoRuleParsedListItem] = []
        var seenDetailURLs: Set<String> = []
        var droppedCount: Int = 0

        for candidate: Element in candidates {
            let title: String = try self.extract(
                from: candidate,
                rule: fields.title,
                pageURL: pageURL
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let detailURLString: String = try self.extract(
                from: candidate,
                rule: fields.detailURL,
                pageURL: pageURL
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            guard title.isEmpty == false,
                  let detailURL: URL = self.absoluteHTTPURL(detailURLString, relativeTo: pageURL),
                  seenDetailURLs.insert(detailURL.absoluteString).inserted else {
                droppedCount += 1
                continue
            }

            let idCode: String? = try fields.idCode.flatMap { idRule in
                return try self.optionalExtract(from: candidate, rule: idRule, pageURL: pageURL)
            }
            let coverURL: URL? = try fields.cover.flatMap { coverRule in
                guard let value: String = try self.optionalExtract(
                    from: candidate,
                    rule: coverRule,
                    pageURL: pageURL
                ) else {
                    return nil
                }
                return self.absoluteHTTPURL(value, relativeTo: pageURL)
            }
            let latestText: String? = try fields.latestText.flatMap { latestRule in
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

    func parseDetail(
        html: String,
        pageURL: URL,
        rule: VideoDetailRule
    ) throws -> VideoRuleParsedDetail {
        guard rule.effectiveSourceStrategy.usesDOM,
              let fields: VideoDetailFields = rule.fields else {
            throw VideoRuleSourceParsingError.incompleteDOMRule(kind: "detail", ruleID: rule.id)
        }
        let document: Document = try SwiftSoup.parse(html, pageURL.absoluteString)
        guard try self.readyMatched(in: document, rule: rule.ready, pageURL: pageURL) else {
            return VideoRuleParsedDetail(
                metadata: VideoRuleParsedDetailMetadata(
                    idCode: nil,
                    title: nil,
                    coverURL: nil,
                    description: nil,
                    attributes: []
                ),
                readyMatched: false
            )
        }

        let idCode: String? = try fields.idCode.flatMap { fieldRule in
            return try self.optionalExtract(from: document, rule: fieldRule, pageURL: pageURL)
        }
        let title: String? = try self.optionalExtract(
            from: document,
            rule: fields.title,
            pageURL: pageURL
        )
        let coverURL: URL? = try fields.cover.flatMap { fieldRule in
            guard let value: String = try self.optionalExtract(
                from: document,
                rule: fieldRule,
                pageURL: pageURL
            ) else {
                return nil
            }
            return self.absoluteHTTPURL(value, relativeTo: pageURL)
        }
        let description: String? = try fields.description.flatMap { fieldRule in
            return try self.optionalExtract(from: document, rule: fieldRule, pageURL: pageURL)
        }
        let attributes: [VideoRuleParsedDetailAttribute] = try (fields.metadata ?? []).compactMap { field in
            guard let value: String = try self.optionalExtract(
                from: document,
                rule: field.value,
                pageURL: pageURL
            ) else {
                return nil
            }
            return VideoRuleParsedDetailAttribute(
                id: field.id,
                label: self.nonEmpty(field.label),
                value: value
            )
        }

        return VideoRuleParsedDetail(
            metadata: VideoRuleParsedDetailMetadata(
                idCode: idCode,
                title: title,
                coverURL: coverURL,
                description: description,
                attributes: attributes
            ),
            readyMatched: true
        )
    }

    func parseEpisodes(
        html: String,
        pageURL: URL,
        rule: VideoEpisodeRule
    ) throws -> VideoRuleParsedEpisodes {
        guard rule.effectiveSourceStrategy.usesDOM,
              let itemRule: ExtractRule = rule.item,
              let fields: VideoEpisodeFields = rule.fields else {
            throw VideoRuleSourceParsingError.incompleteDOMRule(kind: "episode", ruleID: rule.id)
        }
        let document: Document = try SwiftSoup.parse(html, pageURL.absoluteString)
        guard try self.readyMatched(in: document, rule: rule.ready, pageURL: pageURL) else {
            return VideoRuleParsedEpisodes(
                groups: [],
                readyMatched: false,
                candidateCount: 0,
                droppedCount: 0
            )
        }

        let groups: [VideoRuleParsedEpisodeGroup]
        if let groupRule: VideoEpisodeGroupDOMRule = rule.group {
            let groupElements: [Element] = try self.selectedElements(
                from: document,
                rule: groupRule.item
            )
            groups = try groupElements.map { groupElement in
                return try self.parseEpisodeGroup(
                    in: groupElement,
                    groupRule: groupRule,
                    itemRule: itemRule,
                    fields: fields,
                    sort: rule.sort,
                    pageURL: pageURL
                )
            }
        } else {
            groups = [
                try self.parseEpisodeGroup(
                    in: document,
                    groupRule: nil,
                    itemRule: itemRule,
                    fields: fields,
                    sort: rule.sort,
                    pageURL: pageURL
                )
            ]
        }

        return VideoRuleParsedEpisodes(
            groups: groups,
            readyMatched: true,
            candidateCount: groups.reduce(0) { $0 + $1.candidateCount },
            droppedCount: groups.reduce(0) { $0 + $1.droppedCount }
        )
    }

    func parsePlayback(
        html: String,
        pageURL: URL,
        rule: VideoPlaybackRule
    ) throws -> VideoRuleParsedPlayback {
        let document: Document = try SwiftSoup.parse(html, pageURL.absoluteString)
        guard try self.readyMatched(in: document, rule: rule.ready, pageURL: pageURL) else {
            return VideoRuleParsedPlayback(
                mediaURLs: [],
                mediaCandidateCount: 0,
                invalidMediaURLCount: 0,
                iframeURLs: [],
                iframeCandidateCount: 0,
                invalidIframeURLCount: 0,
                readyMatched: false
            )
        }

        let mediaCandidates: (values: [String], count: Int) = try self.playbackCandidateValues(
            from: document,
            rule: rule.media?.url,
            pageURL: pageURL
        )
        let iframeCandidates: (values: [String], count: Int) = try self.playbackCandidateValues(
            from: document,
            rule: rule.iframe?.url,
            pageURL: pageURL
        )
        let mediaResult: (urls: [URL], invalidCount: Int) = self.playbackURLs(
            mediaCandidates.values,
            relativeTo: pageURL
        )
        let iframeResult: (urls: [URL], invalidCount: Int) = self.playbackURLs(
            iframeCandidates.values,
            relativeTo: pageURL
        )
        return VideoRuleParsedPlayback(
            mediaURLs: mediaResult.urls,
            mediaCandidateCount: mediaCandidates.count,
            invalidMediaURLCount: mediaResult.invalidCount,
            iframeURLs: iframeResult.urls,
            iframeCandidateCount: iframeCandidates.count,
            invalidIframeURLCount: iframeResult.invalidCount,
            readyMatched: true
        )
    }

    private func playbackCandidateValues(
        from element: Element,
        rule: ExtractRule?,
        pageURL: URL
    ) throws -> (values: [String], count: Int) {
        guard let rule: ExtractRule else {
            return ([], 0)
        }
        let selected: [Element] = try self.selectedElements(from: element, rule: rule)
        let values: [String] = try selected.compactMap { selectedElement in
            let value: String = try self.playbackValue(
                from: selectedElement,
                rule: rule,
                pageURL: pageURL
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        if values.isEmpty == false {
            return (values, selected.count)
        }
        for fallback: ExtractRule in rule.fallback ?? [] {
            let fallbackValues: (values: [String], count: Int) = try self.playbackCandidateValues(
                from: element,
                rule: fallback,
                pageURL: pageURL
            )
            if fallbackValues.values.isEmpty == false {
                return fallbackValues
            }
        }
        return ([], selected.count)
    }

    private func playbackURLs(
        _ values: [String],
        relativeTo pageURL: URL
    ) -> (urls: [URL], invalidCount: Int) {
        var urls: [URL] = []
        var seenURLKeys: Set<String> = []
        var invalidCount: Int = 0
        for value: String in values {
            guard let url: URL = self.absoluteHTTPURL(value, relativeTo: pageURL) else {
                invalidCount += 1
                continue
            }
            if seenURLKeys.insert(self.canonicalURLKey(url)).inserted {
                urls.append(url)
            }
        }
        return (urls, invalidCount)
    }

    private func playbackValue(
        from element: Element,
        rule: ExtractRule,
        pageURL: URL
    ) throws -> String {
        let rawValue: String
        switch rule.function {
        case .text:
            rawValue = try element.text()
        case .attr:
            rawValue = try self.attributeValue(from: element, expression: rule.param ?? "")
        case .raw:
            rawValue = try element.outerHtml()
        case .url:
            let attributeValue: String = try self.attributeValue(
                from: element,
                expression: rule.param ?? "href"
            )
            rawValue = self.absoluteURLString(attributeValue, relativeTo: pageURL)
        case .html, .decodeBase64, .removingPercentEncoding, .addingPercentEncoding,
             .replace, .decompressFromBase64, .reversed, .regexReplacement:
            throw VideoRuleSourceParsingError.unsupportedFunction(rule.function)
        }
        return try self.applyRegex(
            to: rawValue,
            regex: rule.regex,
            replacement: rule.replacement
        )
    }

    private func parseEpisodeGroup(
        in container: Element,
        groupRule: VideoEpisodeGroupDOMRule?,
        itemRule: ExtractRule,
        fields: VideoEpisodeFields,
        sort: VideoEpisodeSort?,
        pageURL: URL
    ) throws -> VideoRuleParsedEpisodeGroup {
        let groupIDCode: String? = try groupRule.flatMap { groupRule in
            return try groupRule.idCode.flatMap { fieldRule in
                return try self.optionalExtract(from: container, rule: fieldRule, pageURL: pageURL)
            }
        }
        let groupTitle: String? = try groupRule.flatMap { groupRule in
            return try groupRule.title.flatMap { fieldRule in
                return try self.optionalExtract(from: container, rule: fieldRule, pageURL: pageURL)
            }
        }
        let candidates: [Element] = try self.selectedElements(from: container, rule: itemRule)
        var episodes: [VideoRuleParsedEpisode] = []
        var seenPlayURLs: Set<String> = []
        var droppedCount: Int = 0

        for candidate: Element in candidates {
            let title: String = try self.extract(
                from: candidate,
                rule: fields.title,
                pageURL: pageURL
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let playURLValue: String = try self.extract(
                from: candidate,
                rule: fields.playURL,
                pageURL: pageURL
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.isEmpty == false,
                  let playURL: URL = self.absoluteHTTPURL(playURLValue, relativeTo: pageURL),
                  seenPlayURLs.insert(self.canonicalURLKey(playURL)).inserted else {
                droppedCount += 1
                continue
            }

            let idCode: String? = try fields.idCode.flatMap { fieldRule in
                return try self.optionalExtract(from: candidate, rule: fieldRule, pageURL: pageURL)
            }
            let order: Double? = try fields.order.flatMap { fieldRule in
                guard let value: String = try self.optionalExtract(
                    from: candidate,
                    rule: fieldRule,
                    pageURL: pageURL
                ) else {
                    return nil
                }
                return Double(value)
            }
            let isRestricted: Bool? = try self.scalarMatch(
                from: candidate,
                rule: fields.restriction,
                pageURL: pageURL
            )
            let isPaid: Bool? = try self.scalarMatch(
                from: candidate,
                rule: fields.paid,
                pageURL: pageURL
            )

            episodes.append(
                VideoRuleParsedEpisode(
                    idCode: idCode,
                    title: title,
                    playURL: playURL,
                    order: order,
                    isRestricted: isRestricted,
                    isPaid: isPaid
                )
            )
        }

        return VideoRuleParsedEpisodeGroup(
            idCode: groupIDCode,
            title: groupTitle,
            episodes: self.sortedEpisodes(episodes, sort: sort),
            candidateCount: candidates.count,
            droppedCount: droppedCount
        )
    }

    private func scalarMatch(
        from element: Element,
        rule: VideoDOMScalarMatchRule?,
        pageURL: URL
    ) throws -> Bool? {
        guard let rule: VideoDOMScalarMatchRule,
              let value: String = try self.optionalExtract(
                  from: element,
                  rule: rule.value,
                  pageURL: pageURL
              ) else {
            return nil
        }
        let normalizedValues: Set<String> = Set(rule.matchingValues.compactMap { self.nonEmpty($0) })
        return normalizedValues.contains(value)
    }

    private func sortedEpisodes(
        _ episodes: [VideoRuleParsedEpisode],
        sort: VideoEpisodeSort?
    ) -> [VideoRuleParsedEpisode] {
        guard let sort: VideoEpisodeSort, sort != .source else {
            return episodes
        }
        return episodes.enumerated().sorted { lhs, rhs in
            switch (lhs.element.order, rhs.element.order) {
            case let (left?, right?):
                if left == right {
                    return lhs.offset < rhs.offset
                }
                return sort == .ascending ? left < right : left > right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    private func readyMatched(
        in document: Document,
        rule: ExtractRule?,
        pageURL: URL
    ) throws -> Bool {
        guard let rule: ExtractRule else {
            return true
        }
        return try self.extract(from: document, rule: rule, pageURL: pageURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
    }

    private func canonicalURLKey(_ url: URL) -> String {
        guard var components: URLComponents = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let normalized: String = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              normalized.isEmpty == false else {
            return nil
        }
        return normalized
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
