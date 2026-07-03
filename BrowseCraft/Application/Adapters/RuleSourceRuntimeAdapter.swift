import Foundation
import BrowseCraftCore

// 中文注释：RuleSourceRuntimeAdapter 是 P3 的 App 层 runtime 适配器，先包装现有 UseCase，不迁移解析实现。
struct RuleSourceRuntimeAdapter: SourceRuntime {
    let source: Source

    private let refreshSourceUseCase: RefreshSourceUseCase
    private let searchSourceUseCase: SearchSourceUseCase
    private let loadChaptersUseCase: LoadChaptersUseCase
    private let loadReaderChapterUseCase: LoadReaderChapterUseCase
    private let definitionBridge: SourceDefinitionBridge
    private let outputBridge: SourceRuntimeOutputBridge

    init(
        source: Source,
        refreshSourceUseCase: RefreshSourceUseCase,
        searchSourceUseCase: SearchSourceUseCase,
        loadChaptersUseCase: LoadChaptersUseCase,
        loadReaderChapterUseCase: LoadReaderChapterUseCase,
        definitionBridge: SourceDefinitionBridge = SourceDefinitionBridge(),
        outputBridge: SourceRuntimeOutputBridge = SourceRuntimeOutputBridge()
    ) {
        self.source = source
        self.refreshSourceUseCase = refreshSourceUseCase
        self.searchSourceUseCase = searchSourceUseCase
        self.loadChaptersUseCase = loadChaptersUseCase
        self.loadReaderChapterUseCase = loadReaderChapterUseCase
        self.definitionBridge = definitionBridge
        self.outputBridge = outputBridge
    }

    var definition: SourceDefinition {
        return self.definitionBridge.definition(from: self.source)
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
            requiresAccount: false
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

        return self.outputBridge.listOutput(
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

        return self.outputBridge.listOutput(
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

        return self.outputBridge.detailOutput(
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

        return self.outputBridge.readerOutput(
            chapter: chapter,
            diagnostics: SourceRuntimeDiagnostics.succeeded()
        )
    }

    func debug(_ input: SourceRuntimeContext) async throws -> SourceDebugOutput {
        try self.validateSource(input)

        return SourceDebugOutput(
            diagnostics: SourceRuntimeDiagnostics.skipped(
                message: "Debug runtime is reserved by P3-2.5 and will be connected after runtime call sites are introduced."
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
        guard context.pageID != nil || context.tabID != nil || context.ruleID != nil else {
            return nil
        }

        return ListContext(
            pageId: context.pageID,
            tabId: context.tabID,
            sectionId: nil,
            listRuleId: context.ruleID,
            sectionRole: nil
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
