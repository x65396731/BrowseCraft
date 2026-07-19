import Foundation
import BrowseCraftCore

// 中文注释：VideoRuleSourceListLoader 只编排 V2 Page/ListRule 的请求和解析，不选择 legacy adapter。
struct VideoRuleSourceListLoader {
    private let pageContentLoader: PageContentLoader
    private let parser: VideoRuleSourceParsingService
    private let renderGuard: VideoHTMLRenderGuard
    private let sourceRequestOverrideResolver: SourceRequestOverrideResolver
    private let paginationResolver: VideoRulePaginationResolver

    init(
        pageContentLoader: PageContentLoader,
        parser: VideoRuleSourceParsingService,
        renderGuard: VideoHTMLRenderGuard = VideoHTMLRenderGuard(),
        sourceRequestOverrideResolver: SourceRequestOverrideResolver = SourceRequestOverrideResolver(),
        paginationResolver: VideoRulePaginationResolver = VideoRulePaginationResolver()
    ) {
        self.pageContentLoader = pageContentLoader
        self.parser = parser
        self.renderGuard = renderGuard
        self.sourceRequestOverrideResolver = sourceRequestOverrideResolver
        self.paginationResolver = paginationResolver
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
        let request: RequestConfig? = self.sourceRequestOverrideResolver.resolve(
            base: entry.effectiveRequest,
            override: input.context.requestOverride
        )
        let response: PageContentResponse = try await self.pageContentLoader.getStringResponse(
            from: requestURL,
            request: request,
            context: SourceRequestContext(
                sourceID: source.id,
                baseURL: URL(string: source.baseURL),
                purpose: .video,
                refererURL: requestURL
            )
        )
        let html: String = response.content
        let parsingURL: URL = response.finalURL
        let renderIssues: [SourceRuntimeIssue] = try self.renderGuard.validateMappableHTML(
            url: parsingURL,
            html: html,
            request: request
        )
        let parsed: VideoRuleParsedList
        do {
            parsed = try self.parser.parseList(
                html: html,
                pageURL: parsingURL,
                rule: listRule
            )
        } catch {
            throw RuleExecutionError.parserDiagnostics(
                stage: .list,
                sourceID: source.id,
                ruleID: listRule.id,
                url: parsingURL.absoluteString,
                operation: "parseVideoV2List",
                selector: listRule.item.selector,
                htmlPreview: Self.htmlPreview(from: html),
                underlyingDescription: error.localizedDescription
            )
        }
        let items: [SourceContentItem] = parsed.items.map { item in
            let stableID: String = item.idCode ?? item.detailURL.absoluteString
            return SourceContentItem(
                id: "\(source.id).video.v2.\(stableID)",
                title: item.title,
                detailURL: item.detailURL,
                coverURL: item.coverURL,
                latestText: item.latestText
            )
        }

        var issues: [SourceRuntimeIssue] = renderIssues
        let shouldStopAtEmptyPage: Bool = paginationResolution.currentPage > 1
            && parsed.candidateCount == 0
            && paginationResolution.stopWhenEmpty == true
        if parsed.candidateCount == 0 {
            if paginationResolution.currentPage == 1 {
                throw RuleExecutionError.selectorEmpty(
                    stage: .list,
                    sourceID: source.id,
                    url: parsingURL.absoluteString,
                    ruleID: listRule.id
                )
            }

            if shouldStopAtEmptyPage {
                issues.append(
                    SourceRuntimeIssue(
                        id: "video.v2.paginationEnded",
                        severity: .info,
                        message: "Video V2 pagination ended at empty page \(paginationResolution.currentPage)."
                    )
                )
            } else if paginationResolution.nextPage != nil {
                issues.append(
                    SourceRuntimeIssue(
                        id: "video.v2.emptyPageContinues",
                        severity: .info,
                        message: "Video V2 page \(paginationResolution.currentPage) was empty and stopWhenEmpty is false."
                    )
                )
            } else {
                issues.append(
                    SourceRuntimeIssue(
                        id: "video.v2.paginationEnded",
                        severity: .info,
                        message: "Video V2 pagination reached its final configured page."
                    )
                )
            }
        } else if items.isEmpty {
            throw RuleExecutionError.ruleConfiguration(
                stage: .list,
                sourceID: source.id,
                reason: "Video V2 list rule \(listRule.id) matched \(parsed.candidateCount) candidates but none produced both title and detailURL."
            )
        }

        if parsed.droppedCount > 0 {
            issues.append(
                SourceRuntimeIssue(
                    id: "video.v2.listItemsDropped",
                    severity: .warning,
                    message: "Video V2 dropped \(parsed.droppedCount) list candidates with missing required fields or duplicate detail URLs."
                )
            )
        }

        let diagnostics: SourceRuntimeDiagnostics
        let requestLogs: [SourceRequestLog] = [
            SourceRequestLog(
                url: requestURL,
                method: request?.method?.rawValue ?? "GET",
                headerCount: request?.headers?.count ?? 0,
                contentLength: html.utf8.count
            )
        ]
        let extractionLogs: [SourceExtractionLog] = [
            SourceExtractionLog(
                field: "list.item",
                selector: listRule.item.selector,
                candidateCount: parsed.candidateCount,
                outputCount: items.count
            )
        ]
        let diagnosticContext: SourceRuntimeDiagnosticContext = SourceRuntimeDiagnosticContext(
            runtimeContext: input.context,
            requestURL: parsingURL
        )
        if parsed.droppedCount > 0, items.isEmpty == false {
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
            items: items,
            pagination: shouldStopAtEmptyPage ? nil : paginationResolution.nextPage,
            diagnostics: diagnostics
        )
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
