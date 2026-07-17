import Foundation

// 中文注释：ComicRuleSourceReaderLoader 是 ComicRuleSourceRuntime 内部阅读页加载边界，只处理 SiteRule-backed source。

/// 中文注释：LoadReaderChapterError 是 enum，负责本模块中的对应职责。
enum LoadReaderChapterError: LocalizedError {
    case noChapterFound(detailURLString: String)
    case noPageImagesFound(chapterURLString: String)

    var errorDescription: String? {
        switch self {
        case .noChapterFound(let detailURLString):
            return "No chapter link was found on detail page: \(detailURLString)"
        case .noPageImagesFound(let chapterURLString):
            return "No page image was found on chapter page: \(chapterURLString)"
        }
    }
}

/// 中文注释：加载一个阅读章节页面，并解析出所有分页图片地址。
/// 中文注释：网络请求留在应用层，具体 HTML 解析通过 ComicRuleSourceParsingService 隔离。
struct ComicRuleSourceReaderLoader {
    private let pageContentLoader: PageContentLoader
    private let comicRuleParser: ComicRuleSourceParsingService

    init(
        pageContentLoader: PageContentLoader,
        comicRuleParser: ComicRuleSourceParsingService
    ) {
        self.pageContentLoader = pageContentLoader
        self.comicRuleParser = comicRuleParser
    }

    /// 中文注释：兼容旧测试和旧装配入口；后续新增 WebView 测试可改用 pageContentLoader 注入。
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
    func execute(
        source: Source,
        item: ContentItem,
        chapterURLString: String? = nil
    ) async throws -> ReaderChapter {
        let resolvedRule: ResolvedSiteRule = RuleResolver().resolve(source.rule)

        RuleExecutionLogger.log(
            stage: .reader,
            event: "request",
            fields: [
                "source": source.id,
                "item": item.id,
                "tab": item.listContext?.tabId ?? "nil",
                "section": item.listContext?.sectionId ?? "nil",
                "listRule": item.listContext?.listRuleId ?? "nil",
                "detailURL": item.detailURL,
                "preferredChapterURL": chapterURLString ?? "nil"
            ]
        )

        let chapterURLString: String = try await self.resolveChapterURLString(
            source: source,
            resolvedRule: resolvedRule,
            item: item,
            preferredChapterURLString: chapterURLString
        )

        RuleExecutionLogger.log(
            stage: .reader,
            event: "resolved-chapter",
            fields: [
                "source": source.id,
                "item": item.id,
                "chapterURL": chapterURLString
            ]
        )

        guard let chapterURL: URL = URL(string: chapterURLString) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .reader,
                sourceID: source.id,
                reason: "Invalid chapter URL: \(chapterURLString)"
            )
        }

        let chapter: ReaderChapter
        if let galleryRule: GalleryRule = resolvedRule.primaryGalleryRule {
            let imageAPIRule: ReaderImageAPIRule? = try self.readerImageAPIRule(
                source: source,
                galleryRule: galleryRule
            )
            if let imageAPIRule: ReaderImageAPIRule,
               let apiChapter: ReaderChapter = try await self.loadImageAPI(
                source: source,
                item: item,
                apiRule: imageAPIRule,
                chapterURLString: chapterURLString,
                fallbackRequest: resolvedRule.primaryGalleryRequest
            ) {
                chapter = apiChapter
            } else {
                RuleExecutionLogger.log(
                    stage: .reader,
                    event: "loader-path",
                    fields: [
                        "source": source.id,
                        "item": item.id,
                        "path": "domSelector",
                        "hasImageAPI": (galleryRule.imageAPI != nil).description,
                        "hasGalleryProtectedResource": (galleryRule.protectedResource != nil).description,
                        "imageItem": galleryRule.imageItem
                    ]
                )
                let html: String = try await self.pageContentLoader.getString(
                    from: chapterURL,
                    request: resolvedRule.primaryGalleryRequest
                )
                chapter = try self.comicRuleParser.parseReader(
                    html: html,
                    source: source,
                    galleryRule: galleryRule,
                    pageURL: chapterURLString,
                    context: item.listContext
                )
            }
        } else {
            chapter = emptyReaderChapter(source: source, pageURL: chapterURLString)
        }

        RuleExecutionLogger.log(
            stage: .reader,
            event: "parsed",
            fields: [
                "source": source.id,
                "item": item.id,
                "chapterURL": chapter.chapterURL,
                "pageCount": chapter.pageImageURLs.count,
                "firstImage": chapter.pageImageURLs.first ?? "nil"
            ]
        )

        if chapter.pageImageURLs.isEmpty {
            throw RuleExecutionError.selectorEmpty(
                stage: .reader,
                sourceID: source.id,
                url: chapterURLString,
                ruleID: resolvedRule.galleryEntry?.ruleID
            )
        }

        return chapter
    }

    /// 中文注释：resolveChapterURLString 方法封装当前类型的一段业务或界面行为。
    private func resolveChapterURLString(
        source: Source,
        resolvedRule: ResolvedSiteRule,
        item: ContentItem,
        preferredChapterURLString: String?
    ) async throws -> String {
        if let preferredChapterURLString: String = preferredChapterURLString {
            RuleExecutionLogger.log(
                stage: .reader,
                event: "resolve-preferred",
                fields: [
                    "source": source.id,
                    "item": item.id,
                    "preferredChapterURL": preferredChapterURLString
                ]
            )
            return preferredChapterURLString
        }

        if shouldTreatDetailURLAsChapter(resolvedRule: resolvedRule, item: item) {
            RuleExecutionLogger.log(
                stage: .reader,
                event: "resolve-direct-chapter",
                fields: [
                    "source": source.id,
                    "item": item.id,
                    "detailURL": item.detailURL
                ]
            )
            return item.detailURL
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
        if let detailRule: DetailRule = resolvedRule.primaryDetailRule {
            chapters = try self.comicRuleParser.parseDetailChapters(
                html: detailHTML,
                source: source,
                detailRule: detailRule,
                pageURL: item.detailURL,
                context: item.listContext
            )
        } else {
            chapters = []
        }

        RuleExecutionLogger.log(
            stage: .detail,
            event: "resolve-candidates",
            fields: [
                "source": source.id,
                "item": item.id,
                "detailURL": item.detailURL,
                "latestText": item.latestText ?? "nil",
                "count": chapters.count,
                "firstURL": chapters.first?.url ?? "nil"
            ]
        )

        if let latestText: String = item.latestText,
           let matchedChapter: ChapterLink = self.chapter(
            matchingLatestText: latestText,
            chapters: chapters
           ) {
            RuleExecutionLogger.log(
                stage: .reader,
                event: "resolve-latest",
                fields: [
                    "source": source.id,
                    "item": item.id,
                    "latestText": latestText,
                    "matchedURL": matchedChapter.url
                ]
            )
            return matchedChapter.url
        }

        if let firstChapter: ChapterLink = chapters.first {
            RuleExecutionLogger.log(
                stage: .reader,
                event: "resolve-first",
                fields: [
                    "source": source.id,
                    "item": item.id,
                    "firstURL": firstChapter.url
                ]
            )
            return firstChapter.url
        }

        throw RuleExecutionError.selectorEmpty(
            stage: .detail,
            sourceID: source.id,
            url: item.detailURL,
            ruleID: resolvedRule.detailEntry?.ruleID
        )
    }

    /// 中文注释：chapter 方法封装当前类型的一段业务或界面行为。
    private func chapter(matchingLatestText latestText: String, chapters: [ChapterLink]) -> ChapterLink? {
        let normalizedLatestText: String = self.normalizedText(latestText)

        return chapters.first { chapter in
            let normalizedChapterTitle: String = self.normalizedText(chapter.title)

            return normalizedChapterTitle.contains(normalizedLatestText)
                || normalizedLatestText.contains(normalizedChapterTitle)
        }
    }

    /// 中文注释：normalizedText 方法封装当前类型的一段业务或界面行为。
    private func normalizedText(_ text: String) -> String {
        var normalizedText: String = text
            .replacingOccurrences(of: "話", with: "话")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while normalizedText.contains("第0") {
            normalizedText = normalizedText.replacingOccurrences(of: "第0", with: "第")
        }

        return normalizedText
    }

    private func readerImageAPIRule(
        source: Source,
        galleryRule: GalleryRule
    ) throws -> ReaderImageAPIRule? {
        if let imageAPI: ReaderImageAPIRule = galleryRule.imageAPI {
            RuleExecutionLogger.log(
                stage: .reader,
                event: "loader-path",
                fields: [
                    "source": source.id,
                    "path": "imageAPI",
                    "hasProtectedResource": (imageAPI.protectedResource != nil).description,
                    "hasResourcePipeline": (imageAPI.resourcePipeline != nil).description
                ]
            )
            return imageAPI
        }

        return nil
    }

    private func loadImageAPI(
        source: Source,
        item: ContentItem,
        apiRule: ReaderImageAPIRule,
        chapterURLString: String,
        fallbackRequest: RequestConfig?
    ) async throws -> ReaderChapter? {
        let apiURLString: String = ComicRuleAPIResolver.replacingTemplatePlaceholders(
            in: apiRule.url,
            source: source,
            item: item,
            chapterURL: chapterURLString,
            rootJSON: nil,
            currentJSON: nil
        )

        guard let apiURL: URL = URL(string: apiURLString) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .reader,
                sourceID: source.id,
                reason: "Invalid reader image API URL: \(apiURLString)"
            )
        }

        RuleExecutionLogger.log(
            stage: .reader,
            event: "image-api-request",
            fields: [
                "source": source.id,
                "item": item.id,
                "apiURL": apiURL.absoluteString,
                "itemPath": apiRule.itemPath,
                "chapterURL": chapterURLString,
                "hasProtectedResource": (apiRule.protectedResource != nil).description,
                "hasResourcePipeline": (apiRule.resourcePipeline != nil).description
            ]
        )

        let request: RequestConfig? = ComicRuleAPIRequestResolver.request(
            base: fallbackRequest,
            override: apiRule.request,
            source: source,
            item: item,
            chapterURL: chapterURLString
        )
        let json: String = try await self.pageContentLoader.getString(
            from: apiURL,
            request: request
        )
        let jsonObject: Any = try JSONSerialization.jsonObject(with: Data(json.utf8))
        if let apiErrorMessage: String = ComicRuleAPIResolver.apiErrorMessage(in: jsonObject) {
            throw RuleExecutionError.sourceAPI(
                stage: .reader,
                sourceID: source.id,
                reason: "Reader image API returned error: \(apiErrorMessage)"
            )
        }
        let itemObjects: [Any] = ComicRuleAPIResolver.jsonValues(at: apiRule.itemPath, in: jsonObject)

        var sortableImagePages: [(url: String, headers: [String: String], resource: ReaderPageResource, order: Double?)] = []
        var imagePages: [(url: String, headers: [String: String], resource: ReaderPageResource)] = []
        var seenURLs: Set<String> = Set<String>()

        for (itemIndex, itemObject): (Int, Any) in itemObjects.enumerated() {
            let resolvedImageURL: String? = self.imageURL(
                apiRule: apiRule,
                source: source,
                item: item,
                chapterURLString: chapterURLString,
                rootJSON: jsonObject,
                currentJSON: itemObject
            )
            guard let resource: ReaderPageResource = try self.readerPageResource(
                apiRule: apiRule,
                source: source,
                chapterURLString: chapterURLString,
                itemIndex: itemIndex,
                imageURL: resolvedImageURL,
                rootJSON: jsonObject,
                currentJSON: itemObject
            ) else {
                continue
            }
            let imageURL: String = resource.displayURLString
            guard imageURL.isEmpty == false,
                  self.isNativelyLoadableImageURL(imageURL),
                  seenURLs.contains(imageURL) == false else {
                continue
            }

            seenURLs.insert(imageURL)
            let imageHeaders: [String: String] = self.imageHeaders(
                apiRule: apiRule,
                source: source,
                item: item,
                chapterURLString: chapterURLString,
                rootJSON: jsonObject,
                currentJSON: itemObject
            )
            imagePages.append((url: imageURL, headers: imageHeaders, resource: resource))
            let order: Double? = apiRule.orderPath.flatMap { path in
                return ComicRuleAPIResolver.doubleValue(
                    ComicRuleAPIResolver.firstJSONValue(at: path, in: itemObject)
                )
            }
            sortableImagePages.append((url: imageURL, headers: imageHeaders, resource: resource, order: order))
        }

        let sortedImagePages: [(url: String, headers: [String: String], resource: ReaderPageResource)] = self.sortedImagePages(
            sortableImagePages,
            sort: apiRule.sort
        )
        let outputImagePages: [(url: String, headers: [String: String], resource: ReaderPageResource)] = sortedImagePages.isEmpty
            ? imagePages
            : sortedImagePages
        let outputImageURLs: [String] = outputImagePages.map(\.url)
        let outputResources: [ReaderPageResource] = outputImagePages.map(\.resource)
        let outputImageHeaders: [String: [String: String]] = Dictionary(
            uniqueKeysWithValues: outputImagePages
                .filter { page in page.headers.isEmpty == false }
                .map { page in (page.url, page.headers) }
        )

        RuleExecutionLogger.log(
            stage: .reader,
            event: "image-api-parsed",
            fields: [
                "source": source.id,
                "item": item.id,
                "chapterURL": chapterURLString,
                "itemCount": itemObjects.count,
                "pageCount": outputImageURLs.count,
                "protectedCount": outputResources.filter { resource in
                    if case .protectedResource = resource {
                        return true
                    }
                    return false
                }.count,
                "imageHeaderPages": outputImageHeaders.count,
                "firstImage": outputImageURLs.first ?? "nil"
            ]
        )

        guard outputImageURLs.isEmpty == false else {
            return nil
        }

        return ReaderChapter(
            sourceId: source.id,
            comicTitle: nil,
            chapterTitle: nil,
            chapterURL: chapterURLString,
            catalogURL: nil,
            previousChapterURL: nil,
            nextChapterURL: nil,
            pageImageURLs: outputImageURLs,
            pageResources: outputResources,
            pageImageHeaders: outputImageHeaders
        )
    }

    private func imageURL(
        apiRule: ReaderImageAPIRule,
        source: Source,
        item: ContentItem,
        chapterURLString: String,
        rootJSON: Any,
        currentJSON: Any
    ) -> String? {
        if let urlTemplate: String = apiRule.urlTemplate,
           urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return ComicRuleAPIResolver.replacingTemplatePlaceholders(
                in: urlTemplate,
                source: source,
                item: item,
                chapterURL: chapterURLString,
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

        return URLResolvingService().absoluteString(rawURL, baseURLString: chapterURLString)
    }

    private func imageHeaders(
        apiRule: ReaderImageAPIRule,
        source: Source,
        item: ContentItem,
        chapterURLString: String,
        rootJSON: Any,
        currentJSON: Any
    ) -> [String: String] {
        guard let headerTemplates: [String: String] = apiRule.imageHeaders,
              headerTemplates.isEmpty == false else {
            return [:]
        }

        return headerTemplates.reduce(into: [String: String]()) { headers, pair in
            let value: String = ComicRuleAPIResolver.replacingTemplatePlaceholders(
                in: pair.value,
                source: source,
                item: item,
                chapterURL: chapterURLString,
                rootJSON: rootJSON,
                currentJSON: currentJSON
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

            if value.isEmpty == false {
                headers[pair.key] = value
            }
        }
    }

    private func readerPageResource(
        apiRule: ReaderImageAPIRule,
        source: Source,
        chapterURLString: String,
        itemIndex: Int,
        imageURL: String?,
        rootJSON: Any,
        currentJSON: Any
    ) throws -> ReaderPageResource? {
        if let resourcePipeline = apiRule.resourcePipeline {
            let displayURLString: String = self.nonEmpty(imageURL)
                ?? self.resourcePipelineDisplayURL(
                    sourceID: source.id,
                    chapterURLString: chapterURLString,
                    itemIndex: itemIndex
                )
            let legacyFallback: LegacyProtectedReaderImageReference?
            switch resourcePipeline.executionPolicy {
            case .pipelineOnly:
                legacyFallback = nil
            case .pipelineWithLegacyFallback:
                guard let protectedResourceRule: ProtectedResourceRule = apiRule.protectedResource,
                      let legacyDisplayURL: String = self.nonEmpty(imageURL) else {
                    throw RuleExecutionError.ruleConfiguration(
                        stage: .reader,
                        sourceID: source.id,
                        reason: "resourcePipeline legacy fallback is missing a resolvable protected image URL"
                    )
                }
                legacyFallback = self.legacyProtectedReference(
                    apiRule: apiRule,
                    source: source,
                    imageURL: legacyDisplayURL,
                    protectedResourceRule: protectedResourceRule,
                    rootJSON: rootJSON,
                    currentJSON: currentJSON
                )
            }

            return .protectedResource(
                ProtectedReaderImageReference(
                    execution: .pipeline(
                        ResourcePipelineReaderImageReference(
                            displayURLString: displayURLString,
                            sourceID: source.id,
                            baseURL: URL(string: source.baseURL),
                            rule: resourcePipeline.pipeline,
                            item: try self.resourcePipelineScope(from: currentJSON),
                            root: try self.resourcePipelineScope(from: rootJSON),
                            context: ComicRuleAPIResolver.ruleContextValues(source: source).mapValues {
                                .string($0)
                            },
                            legacyFallback: legacyFallback
                        )
                    )
                )
            )
        }

        guard let imageURL: String = self.nonEmpty(imageURL) else {
            return nil
        }
        guard let protectedResourceRule: ProtectedResourceRule = apiRule.protectedResource else {
            return .remoteImageURL(imageURL)
        }

        return .protectedResource(
            ProtectedReaderImageReference(
                execution: .legacy(
                    self.legacyProtectedReference(
                        apiRule: apiRule,
                        source: source,
                        imageURL: imageURL,
                        protectedResourceRule: protectedResourceRule,
                        rootJSON: rootJSON,
                        currentJSON: currentJSON
                    )
                )
            )
        )
    }

    private func legacyProtectedReference(
        apiRule: ReaderImageAPIRule,
        source: Source,
        imageURL: String,
        protectedResourceRule: ProtectedResourceRule,
        rootJSON: Any,
        currentJSON: Any
    ) -> LegacyProtectedReaderImageReference {
        let parameters: [String: String] = self.protectedResourceParameters(
            apiRule: apiRule,
            imageURL: imageURL,
            protectedResourceRule: protectedResourceRule,
            rootJSON: rootJSON,
            currentJSON: currentJSON
        )

        return LegacyProtectedReaderImageReference(
            displayURLString: imageURL,
            sourceID: source.id,
            baseURL: URL(string: source.baseURL),
            rule: protectedResourceRule,
            parameters: parameters
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value: String = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }
        return value
    }

    private func resourcePipelineDisplayURL(
        sourceID: String,
        chapterURLString: String,
        itemIndex: Int
    ) -> String {
        let identity: String = [sourceID, chapterURLString]
            .joined(separator: "|")
            .data(using: .utf8)?
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "") ?? "reader"
        return "resource-pipeline://reader/\(identity)/\(itemIndex)"
    }

    private func resourcePipelineScope(
        from jsonObject: Any
    ) throws -> [String: ReaderResourcePipelineValue] {
        if let object: [String: Any] = jsonObject as? [String: Any] {
            return try object.mapValues { value in
                try self.resourcePipelineValue(from: value)
            }
        }
        return ["value": try self.resourcePipelineValue(from: jsonObject)]
    }

    private func resourcePipelineValue(from jsonValue: Any) throws -> ReaderResourcePipelineValue {
        if jsonValue is NSNull {
            return .null
        }
        if let value: String = jsonValue as? String {
            return .string(value)
        }
        if let value: Bool = jsonValue as? Bool {
            return .boolean(value)
        }
        if let value: NSNumber = jsonValue as? NSNumber {
            return .number(value.doubleValue)
        }
        if let value: [String: Any] = jsonValue as? [String: Any] {
            return .object(try value.mapValues { nestedValue in
                try self.resourcePipelineValue(from: nestedValue)
            })
        }
        if let value: [Any] = jsonValue as? [Any] {
            return .array(try value.map { nestedValue in
                try self.resourcePipelineValue(from: nestedValue)
            })
        }

        throw RuleExecutionError.ruleConfiguration(
            stage: .reader,
            sourceID: "unknown",
            reason: "resourcePipeline scope contains an unsupported JSON value"
        )
    }

    private func protectedResourceParameters(
        apiRule: ReaderImageAPIRule,
        imageURL: String,
        protectedResourceRule: ProtectedResourceRule,
        rootJSON: Any,
        currentJSON: Any
    ) -> [String: String] {
        var parameters: [String: String] = [:]

        if let urlTemplate: String = apiRule.urlTemplate {
            self.templateTokens(in: urlTemplate).forEach { token in
                if let value: String = ComicRuleAPIResolver.stringValue(
                    ComicRuleAPIResolver.firstJSONValue(at: token, in: currentJSON)
                ) ?? ComicRuleAPIResolver.stringValue(
                    ComicRuleAPIResolver.firstJSONValue(at: token, in: rootJSON)
                ),
                   value.isEmpty == false {
                    parameters[token] = value
                }
            }
        }

        if let urlComponents: URLComponents = URLComponents(string: imageURL) {
            urlComponents.queryItems?.forEach { item in
                if let value: String = item.value,
                   value.isEmpty == false {
                    parameters[item.name] = value
                }
            }
        }

        return parameters
    }

    private func templateTokens(in template: String) -> [String] {
        let pattern: String = #"\{([^{}]+)\}"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        return regex.matches(
            in: template,
            range: NSRange(template.startIndex..<template.endIndex, in: template)
        )
        .compactMap { match in
            guard match.numberOfRanges == 2,
                  let range: Range<String.Index> = Range(match.range(at: 1), in: template) else {
                return nil
            }

            return String(template[range])
        }
    }

    private func sortedImagePages(
        _ pages: [(url: String, headers: [String: String], resource: ReaderPageResource, order: Double?)],
        sort: ChapterSort?
    ) -> [(url: String, headers: [String: String], resource: ReaderPageResource)] {
        guard let sort: ChapterSort = sort,
              sort != .none,
              pages.contains(where: { page in page.order != nil }) else {
            return []
        }

        return pages.sorted { lhs, rhs in
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
        .map { page in
            return (url: page.url, headers: page.headers, resource: page.resource)
        }
    }

    private func isNativelyLoadableImageURL(_ urlString: String) -> Bool {
        let normalizedURLString: String = urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalizedURLString.hasPrefix("blob:") == false
            && normalizedURLString.hasPrefix("data:") == false
            && normalizedURLString.hasPrefix("about:") == false
            && normalizedURLString.hasPrefix("javascript:") == false
    }
}

private func emptyReaderChapter(source: Source, pageURL: String) -> ReaderChapter {
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
