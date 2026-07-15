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

        if let detailRule: DetailRule = resolvedRule.primaryDetailRule,
           self.shouldPreferDetailAPI(detailRule: detailRule),
           let apiDetail: ChapterDetailContent = try await self.loadDetailAPI(
            source: source,
            item: item,
            detailRule: detailRule
           ) {
            RuleExecutionLogger.log(
                stage: .detail,
                event: "preferred-detail-api-output",
                fields: [
                    "source": source.id,
                    "item": item.id,
                    "detailURL": item.detailURL,
                    "count": apiDetail.chapters.count,
                    "firstURL": apiDetail.chapters.first?.url ?? "nil"
                ]
            )

            return apiDetail
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

    private func shouldPreferDetailAPI(detailRule: DetailRule) -> Bool {
        return detailRule.chapterAPI?.preferAPI == true
    }

    private func loadDetailAPI(
        source: Source,
        item: ContentItem,
        detailRule: DetailRule
    ) async throws -> ChapterDetailContent? {
        guard let apiRule: DetailChapterAPIRule = detailRule.chapterAPI else {
            return nil
        }

        let apiURLString: String = ComicRuleAPIResolver.replacingTemplatePlaceholders(
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

        let request: RequestConfig? = self.detailAPIRequest(
            apiRule: apiRule,
            detailRule: detailRule,
            source: source,
            item: item
        )
        let json: String = try await self.pageContentLoader.getString(
            from: apiURL,
            request: request
        )
        let jsonObject: Any = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let itemObjects: [Any] = ComicRuleAPIResolver.jsonValues(at: apiRule.itemPath, in: jsonObject)

        var chapters: [ChapterLink] = []
        var sortableChapters: [(chapter: ChapterLink, order: Double?)] = []
        var seenURLs: Set<String> = Set<String>()

        for itemObject: Any in itemObjects {
            guard let title: String = ComicRuleAPIResolver.stringValue(
                ComicRuleAPIResolver.firstJSONValue(at: apiRule.titlePath, in: itemObject)
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
                return ComicRuleAPIResolver.doubleValue(
                    ComicRuleAPIResolver.firstJSONValue(at: path, in: itemObject)
                )
            }
            chapters.append(chapter)
            sortableChapters.append((chapter: chapter, order: order))
        }

        let sortedChapters: [ChapterLink] = self.sortedAPIChapters(sortableChapters, sort: apiRule.sort)
        let outputChapters: [ChapterLink] = sortedChapters.isEmpty ? chapters : sortedChapters
        let description: String? = apiRule.descriptionPath.flatMap { path in
            return ComicRuleAPIResolver.stringValue(ComicRuleAPIResolver.firstJSONValue(at: path, in: jsonObject))?
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

    private func detailAPIRequest(
        apiRule: DetailChapterAPIRule,
        detailRule: DetailRule,
        source: Source,
        item: ContentItem
    ) -> RequestConfig? {
        guard let request: RequestConfig = apiRule.request ?? detailRule.request else {
            return nil
        }

        return ComicRuleAPIResolver.request(
            from: request,
            source: source,
            item: item
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
            return ComicRuleAPIResolver.replacingTemplatePlaceholders(
                in: urlTemplate,
                source: source,
                item: item,
                rootJSON: rootJSON,
                currentJSON: currentJSON
            )
        }

        guard let urlPath: String = apiRule.urlPath,
              let rawURL: String = ComicRuleAPIResolver.stringValue(
                ComicRuleAPIResolver.firstJSONValue(at: urlPath, in: currentJSON)
              ) else {
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

}

func shouldTreatDetailURLAsChapter(resolvedRule: ResolvedSiteRule, item: ContentItem) -> Bool {
    if item.detailURL.contains("/chapters/") {
        return true
    }

    return resolvedRule.treatsDetailURLAsChapter
}
