import Foundation
import BrowseCraftCore

// 中文注释：RuleSourceRuntime 只解释 SiteRule JSON 这种 rule-backed source；
// App 总主轴是 SourceRuntime，RSS/Plugin 后续应走各自 runtime，不继续扩张 SiteRule。
struct RuleSourceRuntime: SourceRuntime {
    let source: Source

    private let refreshSourceUseCase: RuleSourceRefreshUseCase
    private let searchSourceUseCase: SearchSourceUseCase
    private let loadChaptersUseCase: RuleSourceLoadChaptersUseCase
    private let loadReaderChapterUseCase: RuleSourceLoadReaderChapterUseCase
    private let definitionMapper: SourceDefinitionMapper
    private let outputMapper: SourceRuntimeOutputMapper

    init(
        source: Source,
        refreshSourceUseCase: RuleSourceRefreshUseCase,
        searchSourceUseCase: SearchSourceUseCase,
        loadChaptersUseCase: RuleSourceLoadChaptersUseCase,
        loadReaderChapterUseCase: RuleSourceLoadReaderChapterUseCase,
        definitionMapper: SourceDefinitionMapper = SourceDefinitionMapper(),
        outputMapper: SourceRuntimeOutputMapper = SourceRuntimeOutputMapper()
    ) {
        self.source = source
        self.refreshSourceUseCase = refreshSourceUseCase
        self.searchSourceUseCase = searchSourceUseCase
        self.loadChaptersUseCase = loadChaptersUseCase
        self.loadReaderChapterUseCase = loadReaderChapterUseCase
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
                    message: "Rule debug runtime is reserved and not connected to the App RuleDebugUseCases yet."
                ),
                SourceRuntimeCapabilityLimitation(
                    capability: .candidateAnalysis,
                    reason: .notConnected,
                    message: "Rule candidate analysis remains in the App debug flow until Core candidate models move in P3-5."
                )
            ]
        )
    }

    func loadList(_ input: SourceListInput) async throws -> SourceListOutput {
        try self.validateSource(input.context)
        try self.validateNoURLOverride(input)

        let listTab: ListTabRule? = self.listTab(for: input.context)
        let items: [ContentItem] = try await self.refreshSourceUseCase.execute(
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

        let result: SearchSourceResult = try await self.searchSourceUseCase.executeWithPagination(
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
            context: input.context
        )
        let chapters: [ChapterLink] = try await self.loadChaptersUseCase.execute(
            source: self.source,
            item: item
        )

        return self.outputMapper.detailOutput(
            chapters: chapters,
            diagnostics: SourceRuntimeDiagnostics.succeeded()
        )
    }

    func loadReader(_ input: SourceReaderInput) async throws -> SourceReaderOutput {
        try self.validateSource(input.context)

        let item: ContentItem = self.contentItem(
            url: input.chapterURL,
            context: input.context
        )
        let chapter: ReaderChapter = try await self.loadReaderChapterUseCase.execute(
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
                message: "Debug runtime is reserved by P3-2.5 and will be connected after runtime call sites are introduced.",
                context: self.diagnosticContext(from: input)
            )
        )
    }

    private var requiresWebView: Bool {
        if self.source.rule.sharedRequest?.needsWebView == true {
            return true
        }

        return self.source.rule.availableListTabs.contains { tab in
            return self.source.rule.request(for: tab)?.needsWebView == true
        }
    }

    private var requiresCookieStore: Bool {
        if self.source.rule.sharedRequest?.cookiePolicy != nil {
            return true
        }

        return self.source.rule.availableListTabs.contains { tab in
            return self.source.rule.request(for: tab)?.cookiePolicy != nil
        }
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

    private func contentItem(url: URL, context: SourceRuntimeContext) -> ContentItem {
        let urlString: String = url.absoluteString
        return ContentItem(
            id: urlString,
            sourceId: self.source.id,
            title: self.source.name,
            detailURL: urlString,
            coverURL: nil,
            type: .comic,
            latestText: nil,
            listOrder: nil,
            listContext: self.listContext(from: context)
        )
    }

    private func listContext(from context: SourceRuntimeContext) -> ListContext? {
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
