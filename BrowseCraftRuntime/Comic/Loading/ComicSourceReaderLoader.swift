import BrowseCraftCore
import BrowseCraftDomain
import Foundation

// 中文注释：ComicSourceReaderLoader 是 ComicSourceRuntime 内部阅读页加载边界，只处理 SiteRule-backed source。

/// 中文注释：LoadReaderChapterError 是 enum，负责本模块中的对应职责。
public enum LoadReaderChapterError: LocalizedError, Sendable {
    case noChapterFound(detailURLString: String)
    case noPageImagesFound(chapterURLString: String)

    public var errorDescription: String? {
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
public struct ComicSourceReaderLoader: Sendable {
    private let pageContentLoader: PageContentLoader
    private let comicRuleParser: ComicRuleSourceParsingService
    private let defaultUserAgent: String

    public init(
        pageContentLoader: PageContentLoader,
        comicRuleParser: ComicRuleSourceParsingService,
        defaultUserAgent: String = ""
    ) {
        self.pageContentLoader = pageContentLoader
        self.comicRuleParser = comicRuleParser
        self.defaultUserAgent = defaultUserAgent
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    public func execute(
        source: Source,
        resolvedRule: ResolvedComicSiteRuleV2,
        readerEntry: ResolvedComicReaderEntry,
        detailEntry: ResolvedComicDetailEntry?,
        item: ContentItem,
        chapterURLString: String? = nil
    ) async throws -> ReaderChapter {
        let galleryRule: ComicGalleryRuleV2 = resolvedRule.galleryRule(for: readerEntry)

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
                "requestScope": readerEntry.effectiveRequest?.scope?.rawValue ?? "nil",
                "needsWebView": readerEntry.effectiveRequest?.needsWebView?.description ?? "nil",
                "autoScroll": readerEntry.effectiveRequest?.autoScroll?.description ?? "nil"
            ]
        )

        let chapterURLString: String = try await self.resolveChapterURLString(
            source: source,
            resolvedRule: resolvedRule,
            detailEntry: detailEntry,
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
        let imageAPIRule: ReaderImageAPIRule? = self.readerImageAPIRule(
            source: source,
            galleryRule: galleryRule
        )
        if let imageAPIRule: ReaderImageAPIRule,
           let apiChapter: ReaderChapter = try await self.loadImageAPI(
            source: source,
            resolvedRule: resolvedRule,
            entry: readerEntry,
            item: item,
            apiRule: imageAPIRule,
            chapterURLString: chapterURLString,
            fallbackRequest: readerEntry.effectiveImageAPIRequest
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
                    "imageItem": galleryRule.images?.item?.selector ?? "nil"
                ]
            )
            let response = try await self.pageContentLoader.loadContent(
                PageLoadRequest(
                    url: chapterURL,
                    requestConfig: readerEntry.effectiveRequest,
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
                resolvedRule: resolvedRule,
                entry: readerEntry,
                item: item,
                pageURL: response.finalURL.absoluteString
            )
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
                ruleID: readerEntry.galleryRuleID
            )
        }

        return chapter
    }

    /// 中文注释：resolveChapterURLString 方法封装当前类型的一段业务或界面行为。
    private func resolveChapterURLString(
        source: Source,
        resolvedRule: ResolvedComicSiteRuleV2,
        detailEntry: ResolvedComicDetailEntry?,
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

        if self.shouldTreatDetailURLAsChapter(
            resolvedRule: resolvedRule,
            detailEntry: detailEntry,
            item: item
        ) {
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

        guard let detailEntry: ResolvedComicDetailEntry else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .detail,
                sourceID: source.id,
                reason: "Comic V2 graph has no detail entry for chapter resolution."
            )
        }

        let detailResponse = try await self.pageContentLoader.loadContent(
            PageLoadRequest(
                url: detailURL,
                requestConfig: detailEntry.effectiveRequest,
                sourceContext: self.requestContext(
                    source: source,
                    purpose: .detail,
                    refererURL: detailURL
                )
            )
        )
        let chapters: [ChapterLink] = try self.comicRuleParser.parseDetailChapters(
            html: detailResponse.content,
            source: source,
            resolvedRule: resolvedRule,
            entry: detailEntry,
            item: item,
            pageURL: detailResponse.finalURL.absoluteString
        )

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
            ruleID: detailEntry.detailRuleID
        )
    }

    private func shouldTreatDetailURLAsChapter(
        resolvedRule: ResolvedComicSiteRuleV2,
        detailEntry: ResolvedComicDetailEntry?,
        item: ContentItem
    ) -> Bool {
        if item.detailURL.contains("/chapters/") {
            return true
        }

        guard let detailEntry else {
            return false
        }
        return resolvedRule.detailRule(for: detailEntry).treatDetailURLAsChapter
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
        galleryRule: ComicGalleryRuleV2
    ) -> ReaderImageAPIRule? {
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
        resolvedRule: ResolvedComicSiteRuleV2,
        entry: ResolvedComicReaderEntry,
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
            override: nil,
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
            resolvedRule: resolvedRule,
            entry: entry,
            item: item,
            chapterURL: chapterURL,
            chapterFinalURL: chapterFinalURL
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
