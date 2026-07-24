import Foundation
import BrowseCraftCore

/// 中文注释：App 只把已经加载完成的文档交给 Core；网络、Cookie、WebView 与凭据仍由 Loader 负责。
/// 中文注释：迁移期间保留 SwiftSoup parser 作为失败/空结果回退，等 App characterization 全部稳定后再删除。
struct CoreComicRuleSourceParser:
    ComicRuleSourceParsingService,
    ComicRuleAPIResponseParsingService,
    ComicRulePaginationParsingService {
    private let parser: BrowseCraftCore.DefaultComicRuleParser
    private let fallbackParser: SwiftSoupComicRuleSourceParser

    init(
        parser: BrowseCraftCore.DefaultComicRuleParser = .init(),
        fallbackParser: SwiftSoupComicRuleSourceParser
    ) {
        self.parser = parser
        self.fallbackParser = fallbackParser
    }

    func parseList(html: String, source: Source) throws -> [ContentItem] {
        return try self.parseList(
            html: html,
            source: source,
            listRule: source.rule.primaryListRule
        )
    }

    func parseList(
        html: String,
        source: Source,
        listRule: ListRule
    ) throws -> [ContentItem] {
        return try self.parseList(
            html: html,
            source: source,
            listRule: listRule,
            context: nil,
            sections: nil
        )
    }

    func parseList(
        html: String,
        source: Source,
        listRule: ListRule,
        context: ListContext?,
        sections: [SectionRule]?
    ) throws -> [ContentItem] {
        guard let pageURL = URL(string: source.baseURL) else {
            return try self.fallbackParser.parseList(
                html: html,
                source: source,
                listRule: listRule,
                context: context,
                sections: sections
            )
        }
        return try self.parseList(
            html: html,
            source: source,
            listRule: listRule,
            context: context,
            sections: sections,
            pageURL: pageURL,
            currentPage: nil
        )
    }

    func parseList(
        html: String,
        source: Source,
        listRule: ListRule,
        context: ListContext?,
        sections: [SectionRule]?,
        pageURL: URL,
        currentPage: Int?
    ) throws -> [ContentItem] {
        do {
            let output = try self.parser.parseList(
                BrowseCraftCore.ComicListParsingInput(
                    document: self.htmlDocument(html, finalURL: pageURL),
                    rule: listRule,
                    sections: sections,
                    listContext: context,
                    runtimeContext: self.runtimeContext(
                        source: source,
                        operation: .list,
                        context: context,
                        ruleID: listRule.id
                    ),
                    currentPage: currentPage
                )
            )
            let items = self.contentItems(
                from: output.items,
                source: source,
                fallbackContext: context
            )
            if items.isEmpty == false {
                if items.contains(where: { $0.coverURL == nil }) {
                    let fallbackItems = try? self.fallbackParser.parseList(
                        html: html,
                        source: source,
                        listRule: listRule,
                        context: context,
                        sections: sections
                    )
                    return self.mergingListFallback(
                        coreItems: items,
                        fallbackItems: fallbackItems ?? []
                    )
                }
                return items
            }
        } catch {
            self.logFallback(
                source: source,
                operation: "list",
                reason: error.localizedDescription
            )
        }

        return try self.fallbackParser.parseList(
            html: html,
            source: source,
            listRule: listRule,
            context: context,
            sections: sections
        )
    }

    func parseSearch(
        html: String,
        source: Source,
        searchRule: SearchRule,
        context: ListContext?
    ) throws -> [ContentItem] {
        guard let pageURL = URL(string: source.baseURL) else {
            return try self.fallbackParser.parseSearch(
                html: html,
                source: source,
                searchRule: searchRule,
                context: context
            )
        }
        return try self.parseSearch(
            html: html,
            source: source,
            searchRule: searchRule,
            context: context,
            pageURL: pageURL,
            currentPage: nil
        )
    }

    func parseSearch(
        html: String,
        source: Source,
        searchRule: SearchRule,
        context: ListContext?,
        pageURL: URL,
        currentPage: Int?
    ) throws -> [ContentItem] {
        do {
            let referencedListRule = source.rule.ruleSets?
                .listRule(id: searchRule.listRuleRef)
            let output = try self.parser.parseSearch(
                BrowseCraftCore.ComicSearchParsingInput(
                    document: self.htmlDocument(html, finalURL: pageURL),
                    rule: searchRule,
                    referencedListRule: referencedListRule,
                    listContext: context,
                    runtimeContext: self.runtimeContext(
                        source: source,
                        operation: .search,
                        context: context,
                        ruleID: searchRule.id
                    ),
                    currentPage: currentPage
                )
            )
            let items = self.contentItems(
                from: output.items,
                source: source,
                fallbackContext: context
            )
            if items.isEmpty == false {
                if items.contains(where: { $0.coverURL == nil }) {
                    let fallbackItems = try? self.fallbackParser.parseSearch(
                        html: html,
                        source: source,
                        searchRule: searchRule,
                        context: context
                    )
                    return self.mergingListFallback(
                        coreItems: items,
                        fallbackItems: fallbackItems ?? []
                    )
                }
                return items
            }
        } catch {
            self.logFallback(
                source: source,
                operation: "search",
                reason: error.localizedDescription
            )
        }

        return try self.fallbackParser.parseSearch(
            html: html,
            source: source,
            searchRule: searchRule,
            context: context
        )
    }

    func parseDetailChapters(
        html: String,
        source: Source,
        pageURL: String
    ) throws -> [ChapterLink] {
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
        let resolvedRule = RuleResolver().resolve(source.rule)
        guard let detailRule = resolvedRule.primaryDetailRule else {
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
        return try self.parseDetail(
            html: html,
            source: source,
            detailRule: detailRule,
            pageURL: pageURL,
            context: context
        ).chapters
    }

    func parseDetail(
        html: String,
        source: Source,
        detailRule: DetailRule,
        pageURL: String,
        context: ListContext?
    ) throws -> ComicRuleParsedDetail {
        guard let finalURL = URL(string: pageURL) else {
            return try self.fallbackParser.parseDetail(
                html: html,
                source: source,
                detailRule: detailRule,
                pageURL: pageURL,
                context: context
            )
        }

        do {
            let output = try self.parser.parseDetail(
                BrowseCraftCore.ComicDetailParsingInput(
                    document: self.htmlDocument(html, finalURL: finalURL),
                    rule: detailRule,
                    listContext: context,
                    runtimeContext: self.runtimeContext(
                        source: source,
                        operation: .detail,
                        context: context,
                        ruleID: detailRule.id
                    )
                )
            )
            let detail = self.detail(from: output)
            if detail.chapters.isEmpty == false {
                return detail
            }

            let fallback = try self.fallbackParser.parseDetail(
                html: html,
                source: source,
                detailRule: detailRule,
                pageURL: pageURL,
                context: context
            )
            return fallback.chapters.isEmpty ? detail : fallback
        } catch {
            self.logFallback(
                source: source,
                operation: "detail",
                reason: error.localizedDescription
            )
            return try self.fallbackParser.parseDetail(
                html: html,
                source: source,
                detailRule: detailRule,
                pageURL: pageURL,
                context: context
            )
        }
    }

    func parseDetailDescription(
        html: String,
        source: Source,
        detailRule: DetailRule,
        pageURL: String,
        context: ListContext?
    ) throws -> String? {
        return try self.parseDetail(
            html: html,
            source: source,
            detailRule: detailRule,
            pageURL: pageURL,
            context: context
        ).description
    }

    func parseReader(
        html: String,
        source: Source,
        pageURL: String
    ) throws -> ReaderChapter {
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
        let resolvedRule = RuleResolver().resolve(source.rule)
        guard let galleryRule = resolvedRule.primaryGalleryRule else {
            return self.emptyReaderChapter(source: source, pageURL: pageURL)
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
        guard let finalURL = URL(string: pageURL) else {
            return try self.fallbackParser.parseReader(
                html: html,
                source: source,
                galleryRule: galleryRule,
                pageURL: pageURL,
                context: context
            )
        }

        do {
            let output = try self.parser.parseReader(
                BrowseCraftCore.ComicReaderParsingInput(
                    document: self.htmlDocument(html, finalURL: finalURL),
                    rule: galleryRule,
                    listContext: context,
                    runtimeContext: self.runtimeContext(
                        source: source,
                        operation: .reader,
                        context: context,
                        ruleID: galleryRule.id
                    )
                )
            )
            let chapter = self.readerChapter(from: output.chapter)
            if chapter.pageImageURLs.isEmpty == false {
                return chapter
            }
        } catch {
            self.logFallback(
                source: source,
                operation: "reader",
                reason: error.localizedDescription
            )
        }

        return try self.fallbackParser.parseReader(
            html: html,
            source: source,
            galleryRule: galleryRule,
            pageURL: pageURL,
            context: context
        )
    }

    func parseChapterAPIResponse(
        json: String,
        finalURL: URL,
        source: Source,
        item: ContentItem,
        apiRule: DetailChapterAPIRule,
        context: ListContext?
    ) throws -> ComicRuleParsedDetail {
        do {
            let output = try self.parser.parseChapterAPIResponse(
                BrowseCraftCore.ComicChapterAPIResponseParsingInput(
                    document: self.jsonDocument(json, finalURL: finalURL),
                    rule: apiRule,
                    itemReference: self.itemReference(
                        source: source,
                        item: item,
                        chapterURL: nil
                    ),
                    sourceBaseURL: URL(string: source.baseURL),
                    ruleContext: self.ruleContext(source: source),
                    runtimeContext: self.runtimeContext(
                        source: source,
                        operation: .detail,
                        context: context,
                        ruleID: nil
                    )
                )
            )
            return self.detail(from: output)
        } catch {
            throw self.apiParsingError(
                error,
                source: source,
                stage: .detail,
                pipelineOnly: false
            )
        }
    }

    func parseImageAPIResponse(
        json: String,
        finalURL: URL,
        source: Source,
        item: ContentItem,
        apiRule: ReaderImageAPIRule,
        chapterURL: URL,
        chapterFinalURL: URL?,
        context: ListContext?
    ) throws -> ReaderChapter {
        do {
            let output = try self.parser.parseImageAPIResponse(
                BrowseCraftCore.ComicImageAPIResponseParsingInput(
                    document: self.jsonDocument(json, finalURL: finalURL),
                    rule: apiRule,
                    itemReference: self.itemReference(
                        source: source,
                        item: item,
                        chapterURL: chapterURL
                    ),
                    chapterURL: chapterURL,
                    chapterFinalURL: chapterFinalURL,
                    sourceBaseURL: URL(string: source.baseURL),
                    ruleContext: self.ruleContext(source: source),
                    runtimeContext: self.runtimeContext(
                        source: source,
                        operation: .reader,
                        context: context,
                        ruleID: nil
                    )
                )
            )
            if output.accessRequirement == .account {
                throw RuleExecutionError.accessRequired(
                    stage: .reader,
                    sourceID: source.id,
                    url: chapterURL.absoluteString
                )
            }
            return self.readerChapter(from: output.chapter)
        } catch let error as RuleExecutionError {
            throw error
        } catch {
            throw self.apiParsingError(
                error,
                source: source,
                stage: .reader,
                pipelineOnly: apiRule.resourcePipeline?.executionPolicy == .pipelineOnly
            )
        }
    }

    func parseNextPageURL(
        html: String,
        source: Source,
        pagination: PaginationRule,
        currentURL: URL
    ) throws -> String? {
        return try self.fallbackParser.parseNextPageURL(
            html: html,
            source: source,
            pagination: pagination,
            currentURL: currentURL
        )
    }

    private func htmlDocument(
        _ html: String,
        finalURL: URL
    ) -> BrowseCraftCore.SourceContentDocument {
        return BrowseCraftCore.SourceContentDocument(
            text: html,
            finalURL: finalURL,
            format: .html,
            mediaType: "text/html"
        )
    }

    private func jsonDocument(
        _ json: String,
        finalURL: URL
    ) -> BrowseCraftCore.SourceContentDocument {
        return BrowseCraftCore.SourceContentDocument(
            text: json,
            finalURL: finalURL,
            format: .json,
            mediaType: "application/json"
        )
    }

    private func runtimeContext(
        source: Source,
        operation: SourceRuntimeOperation,
        context: ListContext?,
        ruleID: String?
    ) -> SourceRuntimeContext {
        return SourceRuntimeContext(
            sourceID: source.id,
            pageID: context?.pageId,
            tabID: context?.tabId,
            sectionID: context?.sectionId,
            sectionRole: context?.sectionRole?.rawValue,
            ruleID: ruleID ?? context?.listRuleId,
            requestOverride: nil,
            debugMode: false,
            operation: operation
        )
    }

    private func contentItems(
        from items: [BrowseCraftCore.SourceContentItem],
        source: Source,
        fallbackContext: ListContext?
    ) -> [ContentItem] {
        return items.enumerated().compactMap { index, item in
            guard let detailURL = item.detailURL else {
                return nil
            }
            return ContentItem(
                id: item.id,
                idCode: item.idCode,
                sourceId: source.id,
                title: item.title,
                detailURL: detailURL.absoluteString,
                coverURL: item.coverURL?.absoluteString,
                type: item.itemReference?.contentType ?? .comic,
                latestText: item.latestText,
                richContent: item.richContent,
                updatedAt: item.updatedAt,
                listOrder: index,
                listContext: self.listContext(
                    from: item.itemReference?.listContext
                ) ?? fallbackContext
            )
        }
    }

    private func mergingListFallback(
        coreItems: [ContentItem],
        fallbackItems: [ContentItem]
    ) -> [ContentItem] {
        let fallbackByURL = Dictionary(
            fallbackItems.map { ($0.detailURL, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return coreItems.map { item in
            guard let fallback = fallbackByURL[item.detailURL] else {
                return item
            }
            var merged = item
            merged.idCode = merged.idCode ?? fallback.idCode
            merged.coverURL = merged.coverURL ?? fallback.coverURL
            merged.latestText = merged.latestText ?? fallback.latestText
            merged.richContent = merged.richContent ?? fallback.richContent
            merged.updatedAt = merged.updatedAt ?? fallback.updatedAt
            return merged
        }
    }

    private func detail(
        from output: BrowseCraftCore.SourceDetailOutput
    ) -> ComicRuleParsedDetail {
        let metadata = output.metadata
        return ComicRuleParsedDetail(
            metadata: ComicRuleParsedDetailMetadata(
                idCode: metadata?.idCode,
                title: metadata?.title,
                coverURL: metadata?.coverURL?.absoluteString,
                description: metadata?.description,
                author: metadata?.author,
                status: metadata?.status,
                category: metadata?.category,
                tags: metadata?.tags ?? [],
                language: metadata?.language,
                publishedAt: metadata?.publishedAt,
                updatedAt: metadata?.updatedAt,
                license: metadata?.license,
                totalImages: metadata?.totalImages,
                photoAlbumURL: metadata?.photoAlbumURL?.absoluteString,
                secondLevelPageURL: metadata?.secondLevelPageURL?.absoluteString
            ),
            chapters: output.chapters.map(self.chapterLink)
        )
    }

    private func itemReference(
        source: Source,
        item: ContentItem,
        chapterURL: URL?
    ) -> BrowseCraftCore.SourceItemReference {
        return BrowseCraftCore.SourceItemReference(
            id: item.id,
            sourceID: source.id,
            title: item.title,
            contentType: item.type,
            detailURL: URL(string: item.detailURL),
            chapterURL: chapterURL,
            coverURL: item.coverURL.flatMap(URL.init(string:)),
            latestText: item.latestText,
            listContext: item.listContext.map { context in
                BrowseCraftCore.SourceItemListContext(
                    pageID: context.pageId,
                    tabID: context.tabId,
                    sectionID: context.sectionId,
                    sectionRole: context.sectionRole?.rawValue,
                    ruleID: context.listRuleId
                )
            },
            handoffIntent: chapterURL == nil ? .detail : .directReader,
            requestOverride: nil,
            runtimeContext: nil,
            idCode: item.idCode
        )
    }

    private func ruleContext(
        source: Source
    ) -> [String: BrowseCraftCore.SourceRuntimeValue] {
        return ComicRuleAPITemplateResolver.ruleContextValues(source: source)
            .mapValues { value in
                BrowseCraftCore.SourceRuntimeValue.string(value)
            }
    }

    private func chapterLink(
        from chapter: BrowseCraftCore.SourceChapter
    ) -> ChapterLink {
        return ChapterLink(
            title: chapter.title,
            subtitle: chapter.subtitle,
            url: chapter.url.absoluteString,
            isRestricted: chapter.isRestricted,
            isPaid: chapter.isPaid,
            navigationChapterURLs: chapter.navigationChapterURLs.map(\.absoluteString),
            navigationChapterTitles: chapter.navigationChapterTitles,
            navigationOrder: chapter.navigationOrder == .ascending
                ? .ascending
                : .descending
        )
    }

    private func readerChapter(
        from chapter: BrowseCraftCore.SourceReaderChapter
    ) -> ReaderChapter {
        return ReaderChapter(
            sourceId: chapter.sourceID,
            comicTitle: chapter.comicTitle,
            chapterTitle: chapter.chapterTitle,
            chapterURL: chapter.chapterURL.absoluteString,
            catalogURL: chapter.catalogURL?.absoluteString,
            previousChapterURL: chapter.previousChapterURL?.absoluteString,
            nextChapterURL: chapter.nextChapterURL?.absoluteString,
            pageImageURLs: chapter.imageURLs.map(\.absoluteString),
            pageResources: chapter.pageResources.map(self.readerPageResource),
            pageImageHeaders: Dictionary(
                uniqueKeysWithValues: chapter.imageHeaders.map {
                    ($0.key.absoluteString, $0.value)
                }
            )
        )
    }

    private func readerPageResource(
        from resource: BrowseCraftCore.SourceReaderPageResource
    ) -> ReaderPageResource {
        switch resource {
        case .remoteImageURL(let url):
            return .remoteImageURL(url.absoluteString)
        case .protectedResource(let reference):
            return .protectedResource(
                self.protectedReference(from: reference)
            )
        }
    }

    private func protectedReference(
        from reference: BrowseCraftCore.SourceProtectedReaderImageReference
    ) -> ProtectedReaderImageReference {
        let displayURL = reference.displayURL?.absoluteString ?? ""
        switch reference.execution {
        case .legacy(let legacy):
            return ProtectedReaderImageReference(
                execution: .legacy(
                    LegacyProtectedReaderImageReference(
                        displayURLString: displayURL,
                        sourceID: reference.sourceID,
                        baseURL: reference.baseURL,
                        rule: legacy.rule,
                        parameters: legacy.parameters
                    )
                )
            )
        case .pipeline(let pipeline):
            return ProtectedReaderImageReference(
                execution: .pipeline(
                    ResourcePipelineReaderImageReference(
                        displayURLString: displayURL,
                        sourceID: reference.sourceID,
                        baseURL: reference.baseURL,
                        rule: pipeline.rule,
                        item: pipeline.item.mapValues(self.pipelineValue),
                        root: pipeline.root.mapValues(self.pipelineValue),
                        context: pipeline.context.mapValues(self.pipelineValue),
                        legacyFallback: pipeline.legacyFallback.map { legacy in
                            LegacyProtectedReaderImageReference(
                                displayURLString: displayURL,
                                sourceID: reference.sourceID,
                                baseURL: reference.baseURL,
                                rule: legacy.rule,
                                parameters: legacy.parameters
                            )
                        }
                    )
                )
            )
        }
    }

    private func pipelineValue(
        _ value: BrowseCraftCore.SourceRuntimeValue
    ) -> ReaderResourcePipelineValue {
        switch value {
        case .string(let value):
            return .string(value)
        case .number(let value):
            return .number(value)
        case .boolean(let value):
            return .boolean(value)
        case .object(let values):
            return .object(values.mapValues(self.pipelineValue))
        case .array(let values):
            return .array(values.map(self.pipelineValue))
        case .null:
            return .null
        }
    }

    private func listContext(
        from context: BrowseCraftCore.SourceItemListContext?
    ) -> ListContext? {
        guard let context else {
            return nil
        }
        return ListContext(
            pageId: context.pageID,
            tabId: context.tabID,
            sectionId: context.sectionID,
            listRuleId: context.ruleID,
            sectionRole: context.sectionRole.flatMap(SectionRole.init(rawValue:))
        )
    }

    private func emptyReaderChapter(
        source: Source,
        pageURL: String
    ) -> ReaderChapter {
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

    private func apiParsingError(
        _ error: Error,
        source: Source,
        stage: RuleExecutionLogger.Stage,
        pipelineOnly: Bool
    ) -> RuleExecutionError {
        guard let parsingError = error as? BrowseCraftCore.SourceParsingError else {
            return .unknown(underlyingDescription: error.localizedDescription)
        }

        switch parsingError {
        case .responseContract(let reason):
            if pipelineOnly, reason.contains("pipelineOnly") {
                return .protectedResource(
                    stage: stage,
                    sourceID: source.id,
                    reason: reason
                )
            }
            if reason.contains("API returned error:") {
                return .sourceAPI(
                    stage: stage,
                    sourceID: source.id,
                    reason: reason
                )
            }
            return .apiResponseContract(
                stage: stage,
                sourceID: source.id,
                reason: reason
            )
        case .incompleteRule:
            return .ruleConfiguration(
                stage: stage,
                sourceID: source.id,
                reason: parsingError.localizedDescription
            )
        default:
            return .responseContract(
                stage: stage,
                sourceID: source.id,
                reason: parsingError.localizedDescription
            )
        }
    }

    private func logFallback(
        source: Source,
        operation: String,
        reason: String
    ) {
        let stage: RuleExecutionLogger.Stage
        switch operation {
        case "search":
            stage = .search
        case "detail":
            stage = .detail
        case "reader":
            stage = .reader
        default:
            stage = .list
        }
        RuleExecutionLogger.log(
            stage: stage,
            event: "core-parser-fallback",
            fields: [
                "source": source.id,
                "operation": operation,
                "reason": reason
            ]
        )
    }
}
