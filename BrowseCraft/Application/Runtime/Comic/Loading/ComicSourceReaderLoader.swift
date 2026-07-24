import Foundation

// 中文注释：ComicSourceReaderLoader 是 ComicSourceRuntime 内部阅读页加载边界，只处理 SiteRule-backed source。

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
struct ComicSourceReaderLoader {
    private let pageContentLoader: PageContentLoader
    private let comicRuleParser: ComicRuleSourceParsingService
    private let defaultUserAgent: String

    init(
        pageContentLoader: PageContentLoader,
        comicRuleParser: ComicRuleSourceParsingService,
        defaultUserAgent: String = ""
    ) {
        self.pageContentLoader = pageContentLoader
        self.comicRuleParser = comicRuleParser
        self.defaultUserAgent = defaultUserAgent
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
                "preferredChapterURL": chapterURLString ?? "nil",
                "requestScope": resolvedRule.primaryGalleryRequest?.scope?.rawValue ?? "nil",
                "needsWebView": resolvedRule.primaryGalleryRequest?.needsWebView?.description ?? "nil",
                "autoScroll": resolvedRule.primaryGalleryRequest?.autoScroll?.description ?? "nil"
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
                if imageAPIRule?.resourcePipeline?.executionPolicy == .pipelineOnly {
                    throw RuleExecutionError.protectedResource(
                        stage: .reader,
                        sourceID: source.id,
                        reason: "Reader image API returned an empty result for pipelineOnly execution"
                    )
                }
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
                let response = try await self.pageContentLoader.loadContent(
                    PageLoadRequest(
                        url: chapterURL,
                        requestConfig: resolvedRule.primaryGalleryRequest,
                        sourceContext: self.requestContext(
                            source: source,
                            purpose: .reader,
                            refererURL: chapterURL
                        )
                    )
                )
                chapter = try self.comicRuleParser.parseReader(
                    html: response.content,
                    source: source,
                    galleryRule: galleryRule,
                    pageURL: response.finalURL.absoluteString,
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
                "firstImage": self.safeResourceURLDescription(chapter.pageImageURLs.first)
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

        let detailResponse = try await self.pageContentLoader.loadContent(
            PageLoadRequest(
                url: detailURL,
                requestConfig: resolvedRule.primaryDetailRequest,
                sourceContext: self.requestContext(
                    source: source,
                    purpose: .detail,
                    refererURL: detailURL
                )
            )
        )
        let chapters: [ChapterLink]
        if let detailRule: DetailRule = resolvedRule.primaryDetailRule {
            chapters = try self.comicRuleParser.parseDetailChapters(
                html: detailResponse.content,
                source: source,
                detailRule: detailRule,
                pageURL: detailResponse.finalURL.absoluteString,
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
        let chapterFinalURL: URL? = try await self.chapterFinalURLIfNeeded(
            source: source,
            apiRule: apiRule,
            chapterURLString: chapterURLString,
            request: fallbackRequest
        )
        let resolvedAPITemplate: String = self.replacingChapterFinalURLPlaceholders(
            in: apiRule.url,
            finalURL: chapterFinalURL
        )
        let apiURLString: String = ComicRuleAPITemplateResolver.replacingTemplatePlaceholders(
            in: resolvedAPITemplate,
            source: source,
            item: item,
            chapterURL: chapterURLString,
            rootJSON: nil,
            currentJSON: nil,
            defaultUserAgent: self.defaultUserAgent
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
                "responsePolicyMode": apiRule.responsePolicy?.mode.rawValue ?? "legacy",
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
            chapterURL: chapterURLString,
            defaultUserAgent: self.defaultUserAgent
        )
        let response: PageContentResponse = try await self.pageContentLoader.loadContent(
            PageLoadRequest(
                url: apiURL,
                requestConfig: request,
                sourceContext: self.requestContext(
                    source: source,
                    purpose: .reader,
                    refererURL: URL(string: chapterURLString) ?? apiURL
                )
            )
        )
        guard let chapterURL = URL(string: chapterURLString) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .reader,
                sourceID: source.id,
                reason: "Invalid chapter URL: \(chapterURLString)"
            )
        }
        let parsedChapter = try self.comicRuleParser.parseImageAPIResponse(
            json: response.content,
            finalURL: response.finalURL,
            source: source,
            item: item,
            apiRule: apiRule,
            chapterURL: chapterURL,
            chapterFinalURL: chapterFinalURL,
            context: item.listContext
        )
        RuleExecutionLogger.log(
            stage: .reader,
            event: "image-api-parsed",
            fields: [
                "source": source.id,
                "item": item.id,
                "parser": "core",
                "chapterURL": chapterURLString,
                "pageCount": parsedChapter.pageImageURLs.count,
                "firstImage": self.safeResourceURLDescription(
                    parsedChapter.pageImageURLs.first
                )
            ]
        )
        return parsedChapter.pageImageURLs.isEmpty ? nil : parsedChapter
    }

    private func chapterFinalURLIfNeeded(
        source: Source,
        apiRule: ReaderImageAPIRule,
        chapterURLString: String,
        request: RequestConfig?
    ) async throws -> URL? {
        let finalURLTokenPrefix = "{chapter.finalURL."
        let apiNeedsFinalURL = apiRule.url.contains(finalURLTokenPrefix)
        let pipelineNeedsFinalURL = apiRule.resourcePipeline?.pipeline.bindings.values.contains { binding in
            binding.source == .context
                && (binding.path?.hasPrefix("chapter.finalURL.") ?? false)
        } ?? false
        guard apiNeedsFinalURL || pipelineNeedsFinalURL else {
            return nil
        }
        guard let chapterURL = URL(string: chapterURLString) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .reader,
                sourceID: source.id,
                reason: "Invalid chapter URL: \(chapterURLString)"
            )
        }
        let response = try await self.pageContentLoader.loadContent(
            PageLoadRequest(
                url: chapterURL,
                requestConfig: request,
                sourceContext: self.requestContext(
                    source: source,
                    purpose: .reader,
                    refererURL: chapterURL
                )
            )
        )
        RuleExecutionLogger.log(
            stage: .reader,
            event: "resolved-final-url",
            fields: [
                "source": source.id,
                "chapterURL": chapterURLString,
                "finalURLHost": response.finalURL.host ?? "nil",
                "queryItemCount": URLComponents(url: response.finalURL, resolvingAgainstBaseURL: false)?.queryItems?.count ?? 0
            ]
        )
        return response.finalURL
    }

    private func replacingChapterFinalURLPlaceholders(in template: String, finalURL: URL?) -> String {
        guard let finalURL,
              let components = URLComponents(url: finalURL, resolvingAgainstBaseURL: false) else {
            return template
        }
        var output = template.replacingOccurrences(
            of: "{chapter.finalURL.absoluteString}",
            with: finalURL.absoluteString
        )
        for queryItem in components.queryItems ?? [] {
            let rawValue = queryItem.value ?? ""
            let absoluteValue = URL(string: rawValue, relativeTo: finalURL)?.absoluteURL.absoluteString ?? rawValue
            output = output.replacingOccurrences(
                of: "{chapter.finalURL.query.\(queryItem.name)}",
                with: rawValue
            )
            output = output.replacingOccurrences(
                of: "{chapter.finalURL.queryAbsolute.\(queryItem.name)}",
                with: absoluteValue
            )
        }
        return output
    }

    /// 中文注释：Reader 图片常带临时签名，只记录 scheme/host/path，避免查询凭据进入日志。
    private func safeResourceURLDescription(_ value: String?) -> String {
        guard let value: String,
              let url: URL = URL(string: value),
              let host: String = url.host else {
            return value == nil ? "nil" : "invalid"
        }

        return "\(url.scheme ?? "unknown")://\(host)\(url.path)"
    }

    private func requestContext(
        source: Source,
        purpose: SourceRequestPurpose,
        refererURL: URL
    ) -> SourceRequestContext {
        return SourceRequestContext(
            sourceID: source.id,
            baseURL: URL(string: source.baseURL),
            purpose: purpose,
            refererURL: refererURL
        )
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
