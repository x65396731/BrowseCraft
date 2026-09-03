import Foundation
import BrowseCraftCore
import BrowseCraftDomain

// 中文注释：ComicSourceRuntime 只解释 SiteRule JSON 这种 rule-backed source；
// App 总主轴是 SourceRuntime，RSS/Plugin 后续应走各自 runtime，不继续扩张 SiteRule。
public struct ComicSourceRuntime: SourceRuntime, SourceSearchRuntime, SourceDetailRuntime, SourceReaderRuntime {
    public let source: Source

    private let resolvedRule: ResolvedComicSiteRuleV2
    private let listLoader: ComicSourceListLoader
    private let searchLoader: ComicSourceSearchLoader
    private let detailLoader: ComicSourceDetailLoader
    private let readerLoader: ComicSourceReaderLoader
    private let definitionMapper: SourceDefinitionMapper
    private let outputMapper: ComicSourceRuntimeMapper

    public init(
        source: Source,
        resolvedRule: ResolvedComicSiteRuleV2,
        listLoader: ComicSourceListLoader,
        searchLoader: ComicSourceSearchLoader,
        detailLoader: ComicSourceDetailLoader,
        readerLoader: ComicSourceReaderLoader,
        definitionMapper: SourceDefinitionMapper = SourceDefinitionMapper(),
        outputMapper: ComicSourceRuntimeMapper = ComicSourceRuntimeMapper()
    ) {
        self.source = source
        self.resolvedRule = resolvedRule
        self.listLoader = listLoader
        self.searchLoader = searchLoader
        self.detailLoader = detailLoader
        self.readerLoader = readerLoader
        self.definitionMapper = definitionMapper
        self.outputMapper = outputMapper
    }

    public var definition: SourceDefinition {
        return self.definitionMapper.definition(from: self.source)
    }

    public var capabilities: SourceRuntimeCapabilities {
        return SourceRuntimeCapabilities(
            supportsSearch: self.resolvedRule.searchEntries.isEmpty == false,
            supportsPagination: true,
            supportsDetail: self.resolvedRule.detailEntries.isEmpty == false,
            supportsReader: self.resolvedRule.readerEntries.isEmpty == false,
            supportsPlayback: false,
            supportsDebug: false,
            supportsCandidateAnalysis: false,
            requiresWebView: self.requiresWebView,
            requiresCookieStore: self.requiresCookieStore,
            requiresAccount: false,
            limitations: [
                SourceRuntimeCapabilityLimitation(
                    capability: .playback,
                    reason: .unsupportedByRuntime,
                    message: "Comic runtime does not expose video playback output."
                ),
                SourceRuntimeCapabilityLimitation(
                    capability: .debug,
                    reason: .notConnected,
                    message: "Rule runtime diagnostics are not available."
                ),
                SourceRuntimeCapabilityLimitation(
                    capability: .candidateAnalysis,
                    reason: .notConnected,
                    message: "Rule candidate analysis is not exposed through this runtime."
                )
            ]
        )
    }

    public func loadList(_ input: SourceListInput) async throws -> SourceListOutput {
        try self.validateSource(input.context)
        try self.validateNoURLOverride(input)

        let entry: ResolvedComicListEntry = try self.listEntry(for: input.context)
        let items: [ContentItem] = try await self.listLoader.execute(
            source: self.source,
            resolvedRule: self.resolvedRule,
            entry: entry,
            page: max(input.page, 1)
        )

        return self.outputMapper.listOutput(
            items: items,
            diagnostics: SourceRuntimeDiagnostics.succeeded()
        )
    }

    public func search(_ input: SourceSearchInput) async throws -> SourceListOutput {
        try self.validateSource(input.context)
        try self.validateSearchOverride(input)

        let entry: ResolvedComicSearchEntry = try self.searchEntry(for: input.context)
        let result: SearchSourceResult = try await self.searchLoader.executeWithPagination(
            source: self.source,
            resolvedRule: self.resolvedRule,
            entry: entry,
            keyword: input.keyword,
            page: max(input.page, 1),
            urlOverride: input.urlOverride?.absoluteString ?? input.context.requestOverride?.url?.absoluteString
        )

        return self.outputMapper.listOutput(
            items: result.items,
            pagination: self.sourcePagination(from: result.pagination),
            diagnostics: SourceRuntimeDiagnostics.succeeded()
        )
    }

    public func loadDetail(_ input: SourceDetailInput) async throws -> SourceDetailOutput {
        try self.validateSource(input.context)

        let item: ContentItem = self.contentItem(
            url: input.detailURL,
            context: input.context,
            reference: input.itemReference
        )
        let entry: ResolvedComicDetailEntry = try self.detailEntry(for: input.context)
        let detailContent: ComicRuleParsedDetail = try await self.detailLoader.execute(
            source: self.source,
            resolvedRule: self.resolvedRule,
            entry: entry,
            item: item
        )

        return self.outputMapper.detailOutput(
            detail: detailContent,
            diagnostics: SourceRuntimeDiagnostics.succeeded()
        )
    }

    public func loadReader(_ input: SourceReaderInput) async throws -> SourceReaderOutput {
        try self.validateSource(input.context)

        let item: ContentItem = self.contentItem(
            url: input.chapterURL,
            context: input.context,
            reference: input.itemReference
        )
        let readerEntry: ResolvedComicReaderEntry = try self.readerEntry(for: input.context)
        let chapter: ReaderChapter = try await self.readerLoader.execute(
            source: self.source,
            resolvedRule: self.resolvedRule,
            readerEntry: readerEntry,
            detailEntry: self.resolvedRule.primaryDetailEntry,
            item: item,
            chapterURLString: input.chapterURL.absoluteString
        )

        return self.outputMapper.readerOutput(
            chapter: chapter,
            diagnostics: SourceRuntimeDiagnostics.succeeded()
        )
    }

    private var requiresWebView: Bool {
        return self.resolvedRule.listEntries.contains { $0.effectiveRequest?.needsWebView == true }
            || self.resolvedRule.searchEntries.contains { $0.effectiveRequest?.needsWebView == true }
            || self.resolvedRule.detailEntries.contains { $0.effectiveRequest?.needsWebView == true }
            || self.resolvedRule.readerEntries.contains { $0.effectiveRequest?.needsWebView == true }
    }

    private var requiresCookieStore: Bool {
        return self.resolvedRule.listEntries.contains { $0.effectiveRequest?.cookiePolicy != nil }
            || self.resolvedRule.searchEntries.contains { $0.effectiveRequest?.cookiePolicy != nil }
            || self.resolvedRule.detailEntries.contains { $0.effectiveRequest?.cookiePolicy != nil }
            || self.resolvedRule.readerEntries.contains { $0.effectiveRequest?.cookiePolicy != nil }
    }

    private func listEntry(for context: SourceRuntimeContext) throws -> ResolvedComicListEntry {
        if let tabID: String = context.tabID,
           let entry: ResolvedComicListEntry = self.resolvedRule.listEntries.first(where: { entry in
               entry.entryID == tabID
           }) {
            return entry
        }

        if let ruleID: String = context.ruleID,
           let entry: ResolvedComicListEntry = self.resolvedRule.listEntries.first(where: { entry in
               entry.ruleID == ruleID
           }) {
            return entry
        }

        if let pageID: String = context.pageID,
           let entry: ResolvedComicListEntry = self.resolvedRule.listEntries.first(where: { entry in
               entry.pageID == pageID || entry.entryID == pageID
           }) {
            return entry
        }

        guard let entry: ResolvedComicListEntry = self.resolvedRule.primaryListEntry else {
            throw SourceRuntimeError.invalidInput("Comic V2 graph has no list entry.")
        }
        return entry
    }

    private func searchEntry(for context: SourceRuntimeContext) throws -> ResolvedComicSearchEntry {
        let entry = self.resolvedRule.searchEntries.first { entry in
            context.ruleID == entry.searchRuleID || context.pageID == entry.pageID
        } ?? self.resolvedRule.primarySearchEntry
        guard let entry else {
            throw SourceRuntimeError.invalidInput("Comic V2 graph has no search entry.")
        }
        return entry
    }

    private func detailEntry(for context: SourceRuntimeContext) throws -> ResolvedComicDetailEntry {
        let entry = self.resolvedRule.detailEntries.first { entry in
            context.ruleID == entry.detailRuleID || context.pageID == entry.pageID
        } ?? self.resolvedRule.primaryDetailEntry
        guard let entry else {
            throw SourceRuntimeError.invalidInput("Comic V2 graph has no detail entry.")
        }
        return entry
    }

    private func readerEntry(for context: SourceRuntimeContext) throws -> ResolvedComicReaderEntry {
        let entry = self.resolvedRule.readerEntries.first { entry in
            context.ruleID == entry.galleryRuleID || context.pageID == entry.pageID
        } ?? self.resolvedRule.primaryReaderEntry
        guard let entry else {
            throw SourceRuntimeError.invalidInput("Comic V2 graph has no reader entry.")
        }
        return entry
    }

    private func contentItem(
        url: URL,
        context: SourceRuntimeContext,
        reference: SourceItemReference?
    ) -> ContentItem {
        let urlString: String = url.absoluteString
        return ContentItem(
            id: reference?.id ?? urlString,
            idCode: reference?.idCode,
            sourceId: self.source.id,
            title: reference?.title ?? self.source.name,
            detailURL: reference?.detailURL?.absoluteString ?? urlString,
            coverURL: reference?.coverURL?.absoluteString,
            type: reference?.contentType ?? .comic,
            latestText: reference?.latestText,
            listOrder: nil,
            listContext: self.listContext(from: reference?.listContext, fallback: context)
        )
    }

    private func listContext(
        from itemContext: SourceItemListContext?,
        fallback context: SourceRuntimeContext
    ) -> ListContext? {
        if let itemContext: SourceItemListContext = itemContext {
            return ListContext(
                pageId: itemContext.pageID,
                tabId: itemContext.tabID,
                sectionId: itemContext.sectionID,
                listRuleId: itemContext.ruleID,
                sectionRole: itemContext.sectionRole.flatMap { SectionRole(rawValue: $0) }
            )
        }

        guard context.pageID != nil || context.tabID != nil || context.sectionID != nil || context.ruleID != nil else {
            return nil
        }

        return ListContext(
            pageId: context.pageID,
            tabId: context.tabID,
            sectionId: context.sectionID,
            listRuleId: context.ruleID,
            sectionRole: context.sectionRole.flatMap { role in
                return SectionRole(rawValue: role)
            }
        )
    }

    private func validateSource(_ context: SourceRuntimeContext) throws {
        guard context.sourceID == self.source.id else {
            throw SourceRuntimeError.sourceMismatch(
                expected: self.source.id,
                actual: context.sourceID
            )
        }
    }

    private func validateNoURLOverride(_ input: SourceListInput) throws {
        if input.urlOverride != nil || input.context.requestOverride?.url != nil {
            throw SourceRuntimeError.unsupported(.listURLOverride)
        }
    }

    private func validateSearchOverride(_ input: SourceSearchInput) throws {
        if input.context.requestOverride?.headers.isEmpty == false {
            throw SourceRuntimeError.unsupported(.requestHeaderOverride)
        }
    }

    private func sourcePagination(from pagination: PaginationResolution?) -> SourcePagination? {
        guard let pagination: PaginationResolution = pagination else {
            return nil
        }

        return SourcePagination.next(
            nextPageURLString: pagination.nextURL,
            nextPage: pagination.nextPage
        )
    }

}
