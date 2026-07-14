import Foundation

// 中文注释：ComicRuleSourceChapterLoader 是 ComicRuleSourceRuntime 内部章节目录加载边界，只处理 SiteRule-backed source。

/// 中文注释：LoadChaptersError 是 enum，负责本模块中的对应职责。
enum LoadChaptersError: LocalizedError {
    case noChaptersFound(detailURLString: String)

    var errorDescription: String? {
        switch self {
        case .noChaptersFound(let detailURLString):
            return "No chapter link was found on detail page: \(detailURLString)"
        }
    }
}

/// 中文注释：加载单个 Library 条目的章节目录。
struct ComicRuleSourceChapterLoader {
    private let pageContentLoader: PageContentLoader
    private let comicRuleParser: ComicRuleSourceParsingService

    init(
        pageContentLoader: PageContentLoader,
        comicRuleParser: ComicRuleSourceParsingService
    ) {
        self.pageContentLoader = pageContentLoader
        self.comicRuleParser = comicRuleParser
    }

    /// 中文注释：兼容旧测试和旧装配入口；普通 HTTP 客户端继续可直接作为页面内容加载器使用。
    init(
        httpClient: HTTPClient,
        comicRuleParser: ComicRuleSourceParsingService
    ) {
        self.init(
            pageContentLoader: httpClient,
            comicRuleParser: comicRuleParser
        )
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute(source: Source, item: ContentItem) async throws -> ChapterDetailContent {
        let resolvedRule: ResolvedSiteRule = RuleResolver().resolve(source.rule)

        RuleExecutionLogger.log(
            stage: .detail,
            event: "request",
            fields: [
                "source": source.id,
                "item": item.id,
                "tab": item.listContext?.tabId ?? "nil",
                "section": item.listContext?.sectionId ?? "nil",
                "listRule": item.listContext?.listRuleId ?? "nil",
                "detailURL": item.detailURL,
                "latestText": item.latestText ?? "nil"
            ]
        )

        if shouldTreatDetailURLAsChapter(resolvedRule: resolvedRule, item: item) {
            RuleExecutionLogger.log(
                stage: .detail,
                event: "direct-chapter",
                fields: [
                    "source": source.id,
                    "item": item.id,
                    "detailURL": item.detailURL
                ]
            )

            return ChapterDetailContent(
                chapters: [
                    ChapterLink(
                        title: item.latestText ?? item.title,
                        url: item.detailURL
                    )
                ],
                description: nil
            )
        }

        guard let detailURL: URL = URL(string: item.detailURL) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .detail,
                sourceID: source.id,
                reason: "Invalid detail URL: \(item.detailURL)"
            )
        }

        let detailHTML: String = try await self.pageContentLoader.getString(
            from: detailURL,
            request: resolvedRule.primaryDetailRequest
        )
        let chapters: [ChapterLink]
        let description: String?
        if let detailRule: DetailRule = resolvedRule.primaryDetailRule {
            let parsedChapters: [ChapterLink] = try self.comicRuleParser.parseDetailChapters(
                html: detailHTML,
                source: source,
                detailRule: detailRule,
                pageURL: item.detailURL,
                context: item.listContext
            )
            let parsedDescription: String? = try self.comicRuleParser.parseDetailDescription(
                html: detailHTML,
                source: source,
                detailRule: detailRule,
                pageURL: item.detailURL,
                context: item.listContext
            )
            let validParsedChapters: [ChapterLink] = self.validChapters(parsedChapters)

            if self.shouldUseDetailAPI(detailRule: detailRule, parsedChapters: parsedChapters),
               let apiDetail: ChapterDetailContent = try await self.loadDetailAPI(
                source: source,
                item: item,
                detailRule: detailRule
               ) {
                chapters = apiDetail.chapters
                description = apiDetail.description ?? parsedDescription
            } else {
                chapters = validParsedChapters
                description = parsedDescription
                if parsedChapters.isEmpty == false,
                   validParsedChapters.isEmpty,
                   detailRule.chapterAPI == nil {
                    RuleExecutionLogger.log(
                        stage: .detail,
                        event: "detail-api-missing",
                        fields: [
                            "source": source.id,
                            "item": item.id,
                            "detailURL": item.detailURL,
                            "invalidChapterCount": parsedChapters.count,
                            "firstInvalidURL": parsedChapters.first?.url ?? "nil"
                        ]
                    )
                }
            }
        } else {
            chapters = []
            description = nil
        }

        RuleExecutionLogger.log(
            stage: .detail,
            event: "parsed",
            fields: [
                "source": source.id,
                "item": item.id,
                "detailURL": item.detailURL,
                "count": chapters.count,
                "firstURL": chapters.first?.url ?? "nil"
            ]
        )

        if chapters.isEmpty {
            throw RuleExecutionError.selectorEmpty(
                stage: .detail,
                sourceID: source.id,
                url: item.detailURL,
                ruleID: resolvedRule.detailEntry?.ruleID
            )
        }

        return ChapterDetailContent(
            chapters: chapters,
            description: description
        )
    }

    private func shouldUseDetailAPI(detailRule: DetailRule, parsedChapters: [ChapterLink]) -> Bool {
        guard let apiRule: DetailChapterAPIRule = detailRule.chapterAPI else {
            return false
        }

        return apiRule.preferAPI == true || parsedChapters.isEmpty || self.hasInvalidChapterURLs(parsedChapters)
    }

    private func loadDetailAPI(
        source: Source,
        item: ContentItem,
        detailRule: DetailRule
    ) async throws -> ChapterDetailContent? {
        guard let apiRule: DetailChapterAPIRule = detailRule.chapterAPI else {
            return nil
        }

        let apiURLString: String = self.replacingTemplatePlaceholders(
            in: apiRule.url,
            source: source,
            item: item,
            rootJSON: nil,
            currentJSON: nil
        )

        guard let apiURL: URL = URL(string: apiURLString) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .detail,
                sourceID: source.id,
                reason: "Invalid detail API URL: \(apiURLString)"
            )
        }

        RuleExecutionLogger.log(
            stage: .detail,
            event: "detail-api-request",
            fields: [
                "source": source.id,
                "item": item.id,
                "apiURL": apiURL.absoluteString,
                "itemPath": apiRule.itemPath
            ]
        )

        let json: String = try await self.pageContentLoader.getString(
            from: apiURL,
            request: apiRule.request ?? detailRule.request
        )
        let jsonObject: Any = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let itemObjects: [Any] = self.jsonValues(at: apiRule.itemPath, in: jsonObject)

        var chapters: [ChapterLink] = []
        var sortableChapters: [(chapter: ChapterLink, order: Double?)] = []
        var seenURLs: Set<String> = Set<String>()

        for itemObject: Any in itemObjects {
            guard let title: String = self.stringValue(
                self.firstJSONValue(at: apiRule.titlePath, in: itemObject)
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
                  title.isEmpty == false,
                  let chapterURL: String = self.chapterURL(
                    apiRule: apiRule,
                    source: source,
                    item: item,
                    rootJSON: jsonObject,
                    currentJSON: itemObject
                  ),
                  chapterURL.isEmpty == false,
                  seenURLs.contains(chapterURL) == false else {
                continue
            }

            seenURLs.insert(chapterURL)
            let chapter: ChapterLink = ChapterLink(title: title, url: chapterURL)
            let order: Double? = apiRule.orderPath.flatMap { path in
                return self.doubleValue(self.firstJSONValue(at: path, in: itemObject))
            }
            chapters.append(chapter)
            sortableChapters.append((chapter: chapter, order: order))
        }

        let sortedChapters: [ChapterLink] = self.sortedAPIChapters(sortableChapters, sort: apiRule.sort)
        let outputChapters: [ChapterLink] = sortedChapters.isEmpty ? chapters : sortedChapters
        let description: String? = apiRule.descriptionPath.flatMap { path in
            return self.stringValue(self.firstJSONValue(at: path, in: jsonObject))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        RuleExecutionLogger.log(
            stage: .detail,
            event: "detail-api-parsed",
            fields: [
                "source": source.id,
                "item": item.id,
                "itemCount": itemObjects.count,
                "chapterCount": outputChapters.count,
                "firstURL": outputChapters.first?.url ?? "nil"
            ]
        )

        guard outputChapters.isEmpty == false else {
            return nil
        }

        return ChapterDetailContent(
            chapters: outputChapters,
            description: description?.isEmpty == false ? description : nil
        )
    }

    private func chapterURL(
        apiRule: DetailChapterAPIRule,
        source: Source,
        item: ContentItem,
        rootJSON: Any,
        currentJSON: Any
    ) -> String? {
        if let urlTemplate: String = apiRule.urlTemplate,
           urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return self.replacingTemplatePlaceholders(
                in: urlTemplate,
                source: source,
                item: item,
                rootJSON: rootJSON,
                currentJSON: currentJSON
            )
        }

        guard let urlPath: String = apiRule.urlPath,
              let rawURL: String = self.stringValue(self.firstJSONValue(at: urlPath, in: currentJSON)) else {
            return nil
        }

        return URLResolvingService().absoluteString(rawURL, baseURLString: item.detailURL)
    }

    private func sortedAPIChapters(
        _ chapters: [(chapter: ChapterLink, order: Double?)],
        sort: ChapterSort?
    ) -> [ChapterLink] {
        guard let sort: ChapterSort = sort,
              sort != .none,
              chapters.contains(where: { pair in pair.order != nil }) else {
            return []
        }

        return chapters.sorted { lhs, rhs in
            let lhsOrder: Double = lhs.order ?? 0
            let rhsOrder: Double = rhs.order ?? 0

            switch sort {
            case .ascending:
                return lhsOrder < rhsOrder
            case .descending:
                return lhsOrder > rhsOrder
            case .none:
                return false
            }
        }
        .map(\.chapter)
    }

    private func hasInvalidChapterURLs(_ chapters: [ChapterLink]) -> Bool {
        return chapters.contains { chapter in
            return self.isInvalidChapterURL(chapter.url)
        }
    }

    private func validChapters(_ chapters: [ChapterLink]) -> [ChapterLink] {
        return chapters.filter { chapter in
            return self.isInvalidChapterURL(chapter.url) == false
        }
    }

    private func isInvalidChapterURL(_ url: String) -> Bool {
        let lowercasedURL: String = url.lowercased()
        return lowercasedURL.contains("undefined")
            || lowercasedURL.contains("null")
            || lowercasedURL.hasSuffix("/0")
    }

    private func replacingTemplatePlaceholders(
        in template: String,
        source: Source,
        item: ContentItem,
        rootJSON: Any?,
        currentJSON: Any?
    ) -> String {
        var output: String = template
        let pattern: String = #"\{([^{}]+)\}"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: pattern) else {
            return output
        }

        let matches: [NSTextCheckingResult] = regex.matches(
            in: template,
            range: NSRange(template.startIndex..<template.endIndex, in: template)
        )

        for match: NSTextCheckingResult in matches.reversed() {
            guard match.numberOfRanges == 2,
                  let fullRange: Range<String.Index> = Range(match.range(at: 0), in: output),
                  let tokenRange: Range<String.Index> = Range(match.range(at: 1), in: template) else {
                continue
            }

            let token: String = String(template[tokenRange])
            let replacement: String = self.templateValue(
                token: token,
                source: source,
                item: item,
                rootJSON: rootJSON,
                currentJSON: currentJSON
            ) ?? ""
            output.replaceSubrange(fullRange, with: replacement)
        }

        return output
    }

    private func templateValue(
        token: String,
        source: Source,
        item: ContentItem,
        rootJSON: Any?,
        currentJSON: Any?
    ) -> String? {
        switch token {
        case "source.id":
            return source.id
        case "source.baseURL", "source.baseUrl":
            return source.baseURL
        case "item.id":
            return item.id
        case "item.title":
            return item.title
        case "detailURL", "item.detailURL":
            return item.detailURL
        case "detailSlug", "item.detailSlug":
            return self.detailSlug(from: item.detailURL)
        case "timestamp":
            return String(Int(Date().timeIntervalSince1970))
        default:
            if let currentJSON: Any = currentJSON,
               let value: String = self.stringValue(self.firstJSONValue(at: token, in: currentJSON)) {
                return value
            }

            if let rootJSON: Any = rootJSON,
               let value: String = self.stringValue(self.firstJSONValue(at: token, in: rootJSON)) {
                return value
            }

            return nil
        }
    }

    private func detailSlug(from detailURL: String) -> String? {
        guard let url: URL = URL(string: detailURL) else {
            return nil
        }

        let lastPathComponent: String = url.lastPathComponent
        if let extensionRange: Range<String.Index> = lastPathComponent.range(of: ".", options: .backwards) {
            return String(lastPathComponent[..<extensionRange.lowerBound])
        }

        return lastPathComponent.isEmpty ? nil : lastPathComponent
    }

    private func firstJSONValue(at path: String, in object: Any) -> Any? {
        return self.jsonValues(at: path, in: object).first
    }

    private func jsonValues(at path: String, in object: Any) -> [Any] {
        let segments: [String] = path
            .split(separator: ".")
            .map(String.init)
            .filter { segment in segment.isEmpty == false }

        return segments.reduce([object]) { values, segment in
            let shouldFlattenArray: Bool = segment.hasSuffix("[]")
            let key: String = shouldFlattenArray ? String(segment.dropLast(2)) : segment
            var nextValues: [Any] = []

            for value: Any in values {
                if key.isEmpty {
                    nextValues.append(value)
                } else if let dictionary: [String: Any] = value as? [String: Any],
                          let child: Any = dictionary[key] {
                    nextValues.append(child)
                }
            }

            if shouldFlattenArray {
                return nextValues.flatMap { value in
                    return value as? [Any] ?? []
                }
            }

            return nextValues
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }
}

func shouldTreatDetailURLAsChapter(resolvedRule: ResolvedSiteRule, item: ContentItem) -> Bool {
    if item.detailURL.contains("/chapters/") {
        return true
    }

    return resolvedRule.treatsDetailURLAsChapter
}
