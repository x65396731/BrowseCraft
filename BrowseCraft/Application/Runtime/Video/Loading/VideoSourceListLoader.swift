import Foundation
import BrowseCraftCore

// 中文注释：Video V2 list loader 在 P1-5 按 sourceStrategy 编排 DOM/API；只有合法 empty 可进入下一分支。
struct VideoSourceListLoader {
    private enum BranchKind {
        case dom
        case api
    }

    private struct BranchOutput {
        let kind: BranchKind
        let items: [SourceContentItem]
        let candidateCount: Int
        let droppedCount: Int
        let pagination: SourcePagination?
        let requestLogs: [SourceRequestLog]
        let extractionLogs: [SourceExtractionLog]
        let issues: [SourceRuntimeIssue]
        let finalURL: URL

        var isEmpty: Bool { self.candidateCount == 0 }
    }

    private let pageContentLoader: PageContentLoader
    private let parser: VideoRuleSourceParsingService
    private let renderGuard: VideoHTMLRenderGuard
    private let sourceRequestOverrideResolver: SourceRequestOverrideResolver
    private let paginationResolver: VideoRulePaginationResolver
    private let apiLoader: VideoSourceAPILoader

    init(
        pageContentLoader: PageContentLoader,
        parser: VideoRuleSourceParsingService,
        renderGuard: VideoHTMLRenderGuard = VideoHTMLRenderGuard(),
        sourceRequestOverrideResolver: SourceRequestOverrideResolver = SourceRequestOverrideResolver(),
        paginationResolver: VideoRulePaginationResolver = VideoRulePaginationResolver(),
        credentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider()
    ) {
        self.pageContentLoader = pageContentLoader
        self.parser = parser
        self.renderGuard = renderGuard
        self.sourceRequestOverrideResolver = sourceRequestOverrideResolver
        self.paginationResolver = paginationResolver
        self.apiLoader = VideoSourceAPILoader(
            pageContentLoader: pageContentLoader,
            sourceRequestOverrideResolver: sourceRequestOverrideResolver,
            credentialProvider: credentialProvider
        )
    }

    func execute(
        source: Source,
        resolvedRule: ResolvedVideoSiteRule,
        input: SourceListInput
    ) async throws -> SourceListOutput {
        let entry: ResolvedVideoListEntry = try self.entry(
            for: input.context,
            resolvedRule: resolvedRule
        )
        let page: VideoPageRule = resolvedRule.page(for: entry)
        let listRule: VideoListRule = resolvedRule.listRule(for: entry)
        let paginationResolution: VideoRulePaginationResolution = try self.paginationResolver.resolve(
            page: page,
            listRule: listRule,
            requestedPage: input.page,
            baseURL: resolvedRule.raw.baseUrl,
            sourceID: source.id
        )
        let requestURL: URL = try self.requestURL(
            configuredPageURL: paginationResolution.configuredPageURL,
            input: input
        )
        let branchOrder: [BranchKind] = try self.branchOrder(
            strategy: listRule.effectiveSourceStrategy,
            page: input.page
        )
        var attempts: [BranchOutput] = []
        for kind: BranchKind in branchOrder {
            let branch: BranchOutput
            switch kind {
            case .dom:
                branch = try await self.loadDOM(
                    source: source,
                    entry: entry,
                    listRule: listRule,
                    input: input,
                    requestURL: requestURL,
                    paginationResolution: paginationResolution
                )
            case .api:
                branch = try await self.loadAPI(
                    source: source,
                    resolvedRule: resolvedRule,
                    entry: entry,
                    listRule: listRule,
                    input: input,
                    refererURL: requestURL
                )
            }
            attempts.append(branch)
            if branch.isEmpty == false {
                return self.output(
                    selected: branch,
                    attempts: attempts,
                    context: input.context,
                    fallbackUsed: attempts.count > 1
                )
            }
        }

        guard let last: BranchOutput = attempts.last else {
            throw SourceRuntimeError.invalidInput("Video V2 list sourceStrategy has no executable branch.")
        }
        if input.page > 1, last.kind == .dom {
            return self.output(
                selected: last,
                attempts: attempts,
                context: input.context,
                fallbackUsed: false
            )
        }
        throw RuleExecutionError.selectorEmpty(
            stage: .list,
            sourceID: source.id,
            url: last.finalURL.absoluteString,
            ruleID: listRule.id
        )
    }

    private func loadDOM(
        source: Source,
        entry: ResolvedVideoListEntry,
        listRule: VideoListRule,
        input: SourceListInput,
        requestURL: URL,
        paginationResolution: VideoRulePaginationResolution
    ) async throws -> BranchOutput {
        let request: RequestConfig? = self.sourceRequestOverrideResolver.resolve(
            base: entry.effectiveListRequest,
            override: input.context.requestOverride
        )
        let response: PageContentResponse = try await self.pageContentLoader.loadContent(
            PageLoadRequest(
                url: requestURL,
                requestConfig: request,
                sourceContext: SourceRequestContext(
                    sourceID: source.id,
                    baseURL: URL(string: source.baseURL),
                    purpose: .video,
                    refererURL: requestURL
                )
            )
        )
        let renderIssues: [SourceRuntimeIssue] = try self.renderGuard.validateMappableHTML(
            url: response.finalURL,
            html: response.content,
            request: request
        )
        let parsed: VideoRuleParsedList
        do {
            parsed = try self.parser.parseList(
                html: response.content,
                pageURL: response.finalURL,
                rule: listRule
            )
        } catch {
            throw RuleExecutionError.parserDiagnostics(
                stage: .list,
                sourceID: source.id,
                ruleID: listRule.id,
                url: response.finalURL.absoluteString,
                operation: "parseVideoV2List",
                selector: listRule.item?.selector,
                htmlPreview: Self.htmlPreview(from: response.content),
                underlyingDescription: error.localizedDescription
            )
        }
        let items: [SourceContentItem] = self.contentItems(source: source, parsed: parsed)
        if parsed.candidateCount > 0, items.isEmpty {
            throw RuleExecutionError.ruleConfiguration(
                stage: .list,
                sourceID: source.id,
                reason: "Video V2 list rule \(listRule.id) matched \(parsed.candidateCount) candidates but none produced both title and detailURL."
            )
        }

        var issues: [SourceRuntimeIssue] = renderIssues
        let shouldStopAtEmptyPage: Bool = paginationResolution.currentPage > 1
            && parsed.candidateCount == 0
            && paginationResolution.stopWhenEmpty == true
        if parsed.candidateCount == 0, paginationResolution.currentPage > 1 {
            issues.append(
                SourceRuntimeIssue(
                    id: shouldStopAtEmptyPage
                        ? "video.v2.paginationEnded"
                        : "video.v2.emptyPageContinues",
                    severity: .info,
                    message: shouldStopAtEmptyPage
                        ? "Video V2 pagination ended at empty page \(paginationResolution.currentPage)."
                        : "Video V2 page \(paginationResolution.currentPage) was empty and stopWhenEmpty is false."
                )
            )
        }
        if parsed.droppedCount > 0 {
            issues.append(
                SourceRuntimeIssue(
                    id: "video.v2.listItemsDropped",
                    severity: .warning,
                    message: "Video V2 dropped \(parsed.droppedCount) DOM list candidates with missing required fields or duplicate detail URLs."
                )
            )
        }
        return BranchOutput(
            kind: .dom,
            items: items,
            candidateCount: parsed.candidateCount,
            droppedCount: parsed.droppedCount,
            pagination: shouldStopAtEmptyPage ? nil : paginationResolution.nextPage,
            requestLogs: [
                SourceRequestLog(
                    url: requestURL,
                    method: request?.method?.rawValue ?? "GET",
                    headerCount: request?.headers?.count ?? 0,
                    contentLength: response.content.utf8.count
                )
            ],
            extractionLogs: [
                SourceExtractionLog(
                    field: "list.dom.item",
                    selector: listRule.item?.selector,
                    candidateCount: parsed.candidateCount,
                    outputCount: items.count
                )
            ],
            issues: issues,
            finalURL: response.finalURL
        )
    }

    private func loadAPI(
        source: Source,
        resolvedRule: ResolvedVideoSiteRule,
        entry: ResolvedVideoListEntry,
        listRule: VideoListRule,
        input: SourceListInput,
        refererURL: URL
    ) async throws -> BranchOutput {
        let branch: VideoRuleAPIBranch<VideoRuleParsedList> = try await self.apiLoader.loadList(
            source: source,
            resolvedRule: resolvedRule,
            entry: entry,
            rule: listRule,
            input: input,
            refererURL: refererURL
        )
        let items: [SourceContentItem] = self.contentItems(source: source, parsed: branch.value)
        var issues: [SourceRuntimeIssue] = []
        if branch.value.droppedCount > 0 {
            issues.append(
                SourceRuntimeIssue(
                    id: "video.v2.listAPIItemsDropped",
                    severity: .warning,
                    message: "Video V2 dropped \(branch.value.droppedCount) list API values with missing required fields or duplicate detail URLs."
                )
            )
        }
        return BranchOutput(
            kind: .api,
            items: items,
            candidateCount: branch.value.candidateCount,
            droppedCount: branch.value.droppedCount,
            pagination: nil,
            requestLogs: [branch.requestLog],
            extractionLogs: [branch.extractionLog],
            issues: issues,
            finalURL: branch.finalURL
        )
    }

    private func output(
        selected: BranchOutput,
        attempts: [BranchOutput],
        context: SourceRuntimeContext,
        fallbackUsed: Bool
    ) -> SourceListOutput {
        let requestLogs: [SourceRequestLog] = attempts.flatMap(\.requestLogs)
        let extractionLogs: [SourceExtractionLog] = attempts.flatMap(\.extractionLogs)
        var issues: [SourceRuntimeIssue] = attempts.flatMap(\.issues)
        if fallbackUsed {
            issues.append(
                SourceRuntimeIssue(
                    id: "video.v2.listFallbackUsed",
                    severity: .info,
                    message: "Video V2 list sourceStrategy used its fallback branch after the preferred branch returned a valid empty result."
                )
            )
        }
        let diagnosticContext = SourceRuntimeDiagnosticContext(
            runtimeContext: context,
            requestURL: selected.finalURL
        )
        let diagnostics: SourceRuntimeDiagnostics
        if selected.droppedCount > 0, selected.items.isEmpty == false {
            diagnostics = SourceRuntimeDiagnostics.partial(
                requestLogs: requestLogs,
                extractionLogs: extractionLogs,
                issues: issues,
                context: diagnosticContext
            )
        } else {
            diagnostics = SourceRuntimeDiagnostics.succeeded(
                requestLogs: requestLogs,
                extractionLogs: extractionLogs,
                issues: issues,
                context: diagnosticContext
            )
        }
        return SourceListOutput(
            items: selected.items,
            pagination: selected.pagination,
            diagnostics: diagnostics
        )
    }

    private func contentItems(
        source: Source,
        parsed: VideoRuleParsedList
    ) -> [SourceContentItem] {
        return parsed.items.map { item in
            let stableID: String = item.idCode ?? item.detailURL.absoluteString
            return SourceContentItem(
                id: "\(source.id).video.v2.\(stableID)",
                idCode: item.idCode,
                title: item.title,
                detailURL: item.detailURL,
                coverURL: item.coverURL,
                latestText: item.latestText
            )
        }
    }

    private func branchOrder(
        strategy: VideoRuleDataSourceStrategy,
        page: Int
    ) throws -> [BranchKind] {
        if page > 1 {
            guard strategy != .apiOnly else {
                throw SourceRuntimeError.unsupported(
                    .custom("Video V2 list API pagination is not part of P1; apiOnly list rules support page 1 only.")
                )
            }
            return [.dom]
        }
        switch strategy {
        case .domOnly:
            return [.dom]
        case .apiOnly:
            return [.api]
        case .domThenAPI:
            return [.dom, .api]
        case .apiThenDOM:
            return [.api, .dom]
        }
    }

    private func entry(
        for context: SourceRuntimeContext,
        resolvedRule: ResolvedVideoSiteRule
    ) throws -> ResolvedVideoListEntry {
        if let pageID: String = context.pageID ?? context.tabID {
            guard let entry: ResolvedVideoListEntry = resolvedRule.listEntries.first(where: { entry in
                return entry.pageID == pageID
            }) else {
                throw SourceRuntimeError.invalidInput("Video V2 page was not found: \(pageID).")
            }
            return entry
        }
        if let ruleID: String = context.ruleID {
            guard let entry: ResolvedVideoListEntry = resolvedRule.listEntries.first(where: { entry in
                return entry.ruleID == ruleID
            }) else {
                throw SourceRuntimeError.invalidInput("Video V2 list rule was not found: \(ruleID).")
            }
            return entry
        }
        guard let entry: ResolvedVideoListEntry = resolvedRule.listEntries.first else {
            throw SourceRuntimeError.invalidInput("Video V2 source has no resolved list entry.")
        }
        return entry
    }

    private func requestURL(
        configuredPageURL: URL,
        input: SourceListInput
    ) throws -> URL {
        let candidate: URL = input.urlOverride
            ?? input.context.requestOverride?.url
            ?? configuredPageURL
        guard let scheme: String = candidate.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              candidate.host != nil else {
            throw SourceRuntimeError.invalidInput(
                "Video V2 request URL override is invalid: \(candidate.absoluteString)."
            )
        }
        return candidate
    }

    private static func htmlPreview(from html: String) -> String {
        let lowercasePrefix: String = String(html.prefix(512)).lowercased()
        let shape: String
        if lowercasePrefix.contains("captcha") || lowercasePrefix.contains("access denied") {
            shape = "blocked-html"
        } else if lowercasePrefix.contains("<html") || lowercasePrefix.contains("<!doctype") {
            shape = "html"
        } else {
            shape = "text"
        }
        return "shape=\(shape) bytes=\(html.utf8.count)"
    }
}
