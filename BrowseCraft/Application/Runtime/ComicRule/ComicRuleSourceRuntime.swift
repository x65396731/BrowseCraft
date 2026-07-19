import Foundation
import BrowseCraftCore

// 中文注释：ComicRuleSourceRuntime 只解释 SiteRule JSON 这种 rule-backed source；
// App 总主轴是 SourceRuntime，RSS/Plugin 后续应走各自 runtime，不继续扩张 SiteRule。
struct ComicRuleSourceRuntime: SourceRuntime {
    let source: Source

    private let listLoader: ComicRuleSourceListLoader
    private let searchLoader: ComicRuleSourceSearchLoader
    private let detailLoader: ComicRuleSourceDetailLoader
    private let readerLoader: ComicRuleSourceReaderLoader
    private let definitionMapper: SourceDefinitionMapper
    private let outputMapper: ComicRuleSourceRuntimeMapper

    init(
        source: Source,
        listLoader: ComicRuleSourceListLoader,
        searchLoader: ComicRuleSourceSearchLoader,
        detailLoader: ComicRuleSourceDetailLoader,
        readerLoader: ComicRuleSourceReaderLoader,
        definitionMapper: SourceDefinitionMapper = SourceDefinitionMapper(),
        outputMapper: ComicRuleSourceRuntimeMapper = ComicRuleSourceRuntimeMapper()
    ) {
        self.source = source
        self.listLoader = listLoader
        self.searchLoader = searchLoader
        self.detailLoader = detailLoader
        self.readerLoader = readerLoader
        self.definitionMapper = definitionMapper
        self.outputMapper = outputMapper
    }

    var definition: SourceDefinition {
        return self.definitionMapper.definition(from: self.source)
    }

    var capabilities: SourceRuntimeCapabilities {
        return SourceRuntimeCapabilities(
            supportsSearch: true,
            supportsPagination: true,
            supportsDetail: true,
            supportsReader: true,
            supportsDebug: false,
            supportsCandidateAnalysis: false,
            requiresWebView: self.requiresWebView,
            requiresCookieStore: self.requiresCookieStore,
            requiresAccount: false,
            limitations: [
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

    func loadList(_ input: SourceListInput) async throws -> SourceListOutput {
        try self.validateSource(input.context)
        try self.validateNoURLOverride(input)

        let listTab: ListTabRule? = self.listTab(for: input.context)
        let items: [ContentItem] = try await self.listLoader.execute(
            source: self.source,
            listTab: listTab,
            page: max(input.page, 1)
        )

        return self.outputMapper.listOutput(
            items: items,
            diagnostics: SourceRuntimeDiagnostics.succeeded()
        )
    }

    func search(_ input: SourceSearchInput) async throws -> SourceListOutput {
        try self.validateSource(input.context)
        try self.validateSearchOverride(input)

        let result: SearchSourceResult = try await self.searchLoader.executeWithPagination(
            source: self.source,
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

    func loadDetail(_ input: SourceDetailInput) async throws -> SourceDetailOutput {
        try self.validateSource(input.context)

        let item: ContentItem = self.contentItem(
            url: input.detailURL,
            context: input.context,
            reference: input.itemReference
        )
        let detailContent: ComicRuleParsedDetail = try await self.detailLoader.execute(
            source: self.source,
            item: item
        )

        return self.outputMapper.detailOutput(
            detail: detailContent,
            diagnostics: SourceRuntimeDiagnostics.succeeded()
        )
    }

    func loadReader(_ input: SourceReaderInput) async throws -> SourceReaderOutput {
        try self.validateSource(input.context)

        let item: ContentItem = self.contentItem(
            url: input.chapterURL,
            context: input.context,
            reference: input.itemReference
        )
        let chapter: ReaderChapter = try await self.readerLoader.execute(
            source: self.source,
            item: item,
            chapterURLString: input.chapterURL.absoluteString
        )

        return self.outputMapper.readerOutput(
            chapter: chapter,
            diagnostics: SourceRuntimeDiagnostics.succeeded()
        )
    }

    func debug(_ input: SourceRuntimeContext) async throws -> SourceDebugOutput {
        try self.validateSource(input)

        return SourceDebugOutput(
            diagnostics: SourceRuntimeDiagnostics.skipped(
                message: "Rule runtime diagnostics are not available.",
                context: self.diagnosticContext(from: input)
            )
        )
    }

    private var requiresWebView: Bool {
        let resolvedRule: ResolvedSiteRule = RuleResolver().resolve(self.source.rule)

        return self.source.rule.availableListTabs.contains { tab in
            return self.source.rule.request(for: tab)?.needsWebView == true
        }
            || resolvedRule.primaryDetailRequest?.needsWebView == true
            || resolvedRule.primaryGalleryRequest?.needsWebView == true
    }

    private var requiresCookieStore: Bool {
        let resolvedRule: ResolvedSiteRule = RuleResolver().resolve(self.source.rule)

        return self.source.rule.availableListTabs.contains { tab in
            return self.source.rule.request(for: tab)?.cookiePolicy != nil
        }
            || resolvedRule.primaryDetailRequest?.cookiePolicy != nil
            || resolvedRule.primaryGalleryRequest?.cookiePolicy != nil
    }

    private func listTab(for context: SourceRuntimeContext) -> ListTabRule? {
        let listTabs: [ListTabRule] = self.source.rule.availableListTabs

        if let tabID: String = context.tabID,
           let tab: ListTabRule = listTabs.first(where: { tab in tab.id == tabID }) {
            return tab
        }

        if let ruleID: String = context.ruleID,
           let tab: ListTabRule = listTabs.first(where: { tab in tab.list.id == ruleID }) {
            return tab
        }

        return listTabs.first
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

    private func diagnosticContext(from context: SourceRuntimeContext) -> SourceRuntimeDiagnosticContext {
        return SourceRuntimeDiagnosticContext(
            runtimeContext: context,
            requestURL: context.requestOverride?.url
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
