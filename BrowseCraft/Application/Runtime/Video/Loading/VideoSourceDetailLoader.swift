import Foundation
import BrowseCraftCore

// 中文注释：P1-5 detail loader 分别执行 detail 与 episode 的显式 sourceStrategy；V2 永不调用 legacy mapper。
struct VideoSourceDetailLoader {
    private enum BranchKind {
        case dom
        case api
    }

    private struct LoadedDocument {
        let requestURL: URL
        let response: PageContentResponse
        let request: RequestConfig?
    }

    private struct DetailBranch {
        let parsed: VideoRuleParsedDetail
        let state: VideoRuleJSONPathState
        let finalURL: URL
    }

    private struct EpisodeBranch {
        let parsed: VideoRuleParsedEpisodes
        let state: VideoRuleJSONPathState
        let finalURL: URL
    }

    private let pageContentLoader: PageContentLoader
    private let parser: VideoRuleSourceParsingService
    private let renderGuard: VideoHTMLRenderGuard
    private let sourceRequestOverrideResolver: SourceRequestOverrideResolver
    private let apiLoader: VideoSourceAPILoader

    init(
        pageContentLoader: PageContentLoader,
        parser: VideoRuleSourceParsingService,
        renderGuard: VideoHTMLRenderGuard = VideoHTMLRenderGuard(),
        sourceRequestOverrideResolver: SourceRequestOverrideResolver = SourceRequestOverrideResolver(),
        credentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider()
    ) {
        self.pageContentLoader = pageContentLoader
        self.parser = parser
        self.renderGuard = renderGuard
        self.sourceRequestOverrideResolver = sourceRequestOverrideResolver
        self.apiLoader = VideoSourceAPILoader(
            pageContentLoader: pageContentLoader,
            sourceRequestOverrideResolver: sourceRequestOverrideResolver,
            credentialProvider: credentialProvider
        )
    }

    func execute(
        source: Source,
        resolvedRule: ResolvedVideoSiteRule,
        input: SourceDetailInput
    ) async throws -> SourceDetailOutput {
        let entry: ResolvedVideoDetailEntry = try self.entry(
            for: input,
            resolvedRule: resolvedRule
        )
        let detailRule: VideoDetailRule = resolvedRule.detailRule(for: entry)
        let episodeRule: VideoEpisodeRule = resolvedRule.episodeRule(for: entry)
        let override: SourceRequestOverride? = input.context.requestOverride
            ?? input.itemReference?.requestOverride
        let requestURL: URL = try self.requestURL(input: input, override: override)
        let detailDOMRequest: RequestConfig? = self.sourceRequestOverrideResolver.resolve(
            base: entry.effectiveDetailRequest,
            override: override
        )
        let episodeDOMRequest: RequestConfig? = self.sourceRequestOverrideResolver.resolve(
            base: entry.effectiveEpisodeRequest,
            override: override
        )

        var documents: [LoadedDocument] = []
        var requestLogs: [SourceRequestLog] = []
        var extractionLogs: [SourceExtractionLog] = []
        var issues: [SourceRuntimeIssue] = []

        func document(for request: RequestConfig?) async throws -> LoadedDocument {
            if let cached: LoadedDocument = documents.first(where: { document in
                return document.request == request
            }) {
                return cached
            }
            let loaded: LoadedDocument = try await self.loadDocument(
                source: source,
                url: requestURL,
                request: request
            )
            documents.append(loaded)
            requestLogs.append(self.requestLog(document: loaded))
            issues.append(contentsOf: try self.renderGuard.validateMappableHTML(
                url: loaded.response.finalURL,
                html: loaded.response.content,
                request: request
            ))
            return loaded
        }

        var selectedDetail: DetailBranch?
        var detailAttemptCount: Int = 0
        for kind: BranchKind in self.branchOrder(detailRule.effectiveSourceStrategy) {
            detailAttemptCount += 1
            let branch: DetailBranch
            switch kind {
            case .dom:
                let loaded: LoadedDocument = try await document(for: detailDOMRequest)
                let parsed: VideoRuleParsedDetail = try self.parseDetail(
                    document: loaded,
                    source: source,
                    rule: detailRule
                )
                let state: VideoRuleJSONPathState = parsed.readyMatched ? .nonEmpty : .empty
                extractionLogs.append(
                    SourceExtractionLog(
                        field: "detail.dom.title",
                        selector: detailRule.fields?.title.selector,
                        candidateCount: parsed.metadata.title == nil ? 0 : 1,
                        outputCount: parsed.metadata.title == nil ? 0 : 1
                    )
                )
                branch = DetailBranch(
                    parsed: parsed,
                    state: state,
                    finalURL: loaded.response.finalURL
                )
            case .api:
                let loaded: VideoRuleAPIBranch<VideoRuleParsedDetail> = try await self.apiLoader.loadDetail(
                    source: source,
                    resolvedRule: resolvedRule,
                    entry: entry,
                    rule: detailRule,
                    input: input
                )
                requestLogs.append(loaded.requestLog)
                extractionLogs.append(loaded.extractionLog)
                branch = DetailBranch(
                    parsed: loaded.value,
                    state: loaded.state,
                    finalURL: loaded.finalURL
                )
            }
            if branch.state == .nonEmpty {
                selectedDetail = branch
                if detailAttemptCount > 1 {
                    issues.append(self.fallbackIssue(owner: "detail"))
                }
                break
            }
        }
        guard let selectedDetail: DetailBranch else {
            throw RuleExecutionError.selectorEmpty(
                stage: .detail,
                sourceID: source.id,
                url: requestURL.absoluteString,
                ruleID: detailRule.id
            )
        }
        guard let title: String = Self.nonEmpty(selectedDetail.parsed.metadata.title) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .detail,
                sourceID: source.id,
                reason: "Video V2 detail rule \(detailRule.id) did not produce the required title field."
            )
        }

        var selectedEpisodes: EpisodeBranch?
        var lastEpisodeBranch: EpisodeBranch?
        var episodeAttemptCount: Int = 0
        for kind: BranchKind in self.branchOrder(episodeRule.effectiveSourceStrategy) {
            episodeAttemptCount += 1
            let branch: EpisodeBranch
            switch kind {
            case .dom:
                let loaded: LoadedDocument = try await document(for: episodeDOMRequest)
                let parsed: VideoRuleParsedEpisodes = try self.parseEpisodes(
                    document: loaded,
                    source: source,
                    rule: episodeRule
                )
                if parsed.candidateCount > 0, parsed.episodes.isEmpty {
                    throw RuleExecutionError.responseContract(
                        stage: .detail,
                        sourceID: source.id,
                        reason: "Video V2 episode rule \(episodeRule.id) matched \(parsed.candidateCount) candidates but none produced both title and playURL."
                    )
                }
                extractionLogs.append(
                    SourceExtractionLog(
                        field: "episode.dom.item",
                        selector: episodeRule.item?.selector,
                        candidateCount: parsed.candidateCount,
                        outputCount: parsed.episodes.count
                    )
                )
                branch = EpisodeBranch(
                    parsed: parsed,
                    state: parsed.readyMatched && parsed.candidateCount > 0 ? .nonEmpty : .empty,
                    finalURL: loaded.response.finalURL
                )
            case .api:
                let loaded: VideoRuleAPIBranch<VideoRuleParsedEpisodes> = try await self.apiLoader.loadEpisodes(
                    source: source,
                    resolvedRule: resolvedRule,
                    entry: entry,
                    rule: episodeRule,
                    input: input
                )
                requestLogs.append(loaded.requestLog)
                extractionLogs.append(loaded.extractionLog)
                branch = EpisodeBranch(
                    parsed: loaded.value,
                    state: loaded.state,
                    finalURL: loaded.finalURL
                )
            }
            lastEpisodeBranch = branch
            if episodeAttemptCount > 1 {
                issues.append(self.fallbackIssue(owner: "episode"))
            }
            if branch.state == .nonEmpty {
                selectedEpisodes = branch
                break
            }
        }
        selectedEpisodes = selectedEpisodes ?? lastEpisodeBranch
        guard let selectedEpisodes: EpisodeBranch else {
            throw SourceRuntimeError.invalidInput("Video V2 episode sourceStrategy has no executable branch.")
        }
        if selectedEpisodes.parsed.droppedCount > 0 {
            issues.append(
                SourceRuntimeIssue(
                    id: "video.v2.episodeItemsDropped",
                    severity: .warning,
                    message: "Video V2 dropped \(selectedEpisodes.parsed.droppedCount) episode candidates with missing required fields or duplicate play URLs inside the same group."
                )
            )
        }

        let chapters: [SourceChapter] = self.chapters(
            source: source,
            parsed: selectedEpisodes.parsed,
            sort: episodeRule.sort ?? episodeRule.episodeAPI?.sort,
            vodID: selectedDetail.parsed.metadata.idCode
                ?? input.itemReference?.idCode
                ?? input.itemReference?.id
                ?? "\(source.id)::\(title)",
            pageID: entry.pageID,
            listRuleID: entry.listRuleID
        )
        let diagnosticContext = SourceRuntimeDiagnosticContext(
            runtimeContext: input.context,
            requestURL: selectedDetail.finalURL
        )
        let diagnostics: SourceRuntimeDiagnostics
        if selectedEpisodes.parsed.droppedCount > 0 {
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
        return SourceDetailOutput(
            metadata: SourceDetailMetadata(
                idCode: selectedDetail.parsed.metadata.idCode ?? input.itemReference?.idCode,
                title: title,
                coverURL: selectedDetail.parsed.metadata.coverURL,
                description: selectedDetail.parsed.metadata.description,
                attributes: selectedDetail.parsed.metadata.attributes.map { attribute in
                    return SourceDetailAttribute(label: attribute.label, value: attribute.value)
                }
            ),
            chapters: chapters,
            diagnostics: diagnostics
        )
    }

    private func entry(
        for input: SourceDetailInput,
        resolvedRule: ResolvedVideoSiteRule
    ) throws -> ResolvedVideoDetailEntry {
        let itemContext: SourceItemListContext? = input.itemReference?.listContext
        let pageID: String? = itemContext?.pageID
            ?? itemContext?.tabID
            ?? input.context.pageID
            ?? input.context.tabID
        let listRuleID: String? = itemContext?.ruleID ?? input.context.ruleID
        var candidates: [ResolvedVideoDetailEntry] = resolvedRule.detailEntries
        if let pageID: String {
            candidates = candidates.filter { $0.pageID == pageID }
            guard candidates.isEmpty == false else {
                throw SourceRuntimeError.invalidInput("Video V2 detail page was not found: \(pageID).")
            }
        }
        if let listRuleID: String {
            candidates = candidates.filter { $0.listRuleID == listRuleID }
            guard candidates.isEmpty == false else {
                throw SourceRuntimeError.invalidInput(
                    "Video V2 detail chain was not found for list rule: \(listRuleID)."
                )
            }
        }
        guard let entry: ResolvedVideoDetailEntry = candidates.first else {
            throw SourceRuntimeError.unsupported(
                .custom("This Video V2 source does not declare a detail/episode rule chain.")
            )
        }
        return entry
    }

    private func branchOrder(_ strategy: VideoRuleDataSourceStrategy) -> [BranchKind] {
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

    private func requestURL(
        input: SourceDetailInput,
        override: SourceRequestOverride?
    ) throws -> URL {
        let candidate: URL = override?.url ?? input.detailURL
        guard let scheme: String = candidate.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              candidate.host != nil else {
            throw SourceRuntimeError.invalidInput(
                "Video V2 detail request URL is invalid: \(candidate.absoluteString)."
            )
        }
        return candidate
    }

    private func loadDocument(
        source: Source,
        url: URL,
        request: RequestConfig?
    ) async throws -> LoadedDocument {
        let response: PageContentResponse = try await self.pageContentLoader.getStringResponse(
            from: url,
            request: request,
            context: SourceRequestContext(
                sourceID: source.id,
                baseURL: URL(string: source.baseURL),
                purpose: .video,
                refererURL: url
            )
        )
        return LoadedDocument(requestURL: url, response: response, request: request)
    }

    private func parseDetail(
        document: LoadedDocument,
        source: Source,
        rule: VideoDetailRule
    ) throws -> VideoRuleParsedDetail {
        do {
            return try self.parser.parseDetail(
                html: document.response.content,
                pageURL: document.response.finalURL,
                rule: rule
            )
        } catch {
            throw RuleExecutionError.parserDiagnostics(
                stage: .detail,
                sourceID: source.id,
                ruleID: rule.id,
                url: document.response.finalURL.absoluteString,
                operation: "parseVideoV2Detail",
                selector: rule.fields?.title.selector,
                htmlPreview: Self.htmlPreview(from: document.response.content),
                underlyingDescription: error.localizedDescription
            )
        }
    }

    private func parseEpisodes(
        document: LoadedDocument,
        source: Source,
        rule: VideoEpisodeRule
    ) throws -> VideoRuleParsedEpisodes {
        do {
            return try self.parser.parseEpisodes(
                html: document.response.content,
                pageURL: document.response.finalURL,
                rule: rule
            )
        } catch {
            throw RuleExecutionError.parserDiagnostics(
                stage: .detail,
                sourceID: source.id,
                ruleID: rule.id,
                url: document.response.finalURL.absoluteString,
                operation: "parseVideoV2Episodes",
                selector: rule.item?.selector,
                htmlPreview: Self.htmlPreview(from: document.response.content),
                underlyingDescription: error.localizedDescription
            )
        }
    }

    private func chapters(
        source: Source,
        parsed: VideoRuleParsedEpisodes,
        sort: VideoEpisodeSort?,
        vodID: String,
        pageID: String,
        listRuleID: String
    ) -> [SourceChapter] {
        let navigationOrder: SourceChapterNavigationOrder = sort == .descending
            ? .descending
            : .ascending
        return parsed.groups.enumerated().flatMap { groupIndex, group in
            let navigationURLs: [URL] = group.episodes.map(\.playURL)
            let navigationTitles: [String?] = group.episodes.map { $0.title }
            let sourceIndex: Int = groupIndex + 1
            let navigationKeys: [String] = group.episodes.enumerated().map { episodeIndex, episode in
                return episode.idCode ?? SourceVideoPlaybackReference.episodeKey(
                    vodID: vodID,
                    sourceIndex: sourceIndex,
                    episodeIndex: episodeIndex + 1
                )
            }
            let groupKey: String
            if let idCode: String = group.idCode {
                groupKey = "id-\(idCode)"
            } else if let title: String = group.title {
                groupKey = "title-\(title)"
            } else {
                groupKey = "index-\(groupIndex)"
            }
            return group.episodes.enumerated().map { episodeIndex, episode in
                let episodeKey: String = navigationKeys[episodeIndex]
                let playbackHandoff = SourceVideoPlaybackHandoff(
                    vodID: vodID,
                    sourceIndex: sourceIndex,
                    episodeIndex: episodeIndex + 1,
                    episodeKey: episodeKey,
                    episodeTitle: episode.title,
                    episodeURLs: navigationURLs,
                    episodeKeys: navigationKeys,
                    episodeTitles: navigationTitles,
                    sourceName: group.title,
                    pageID: pageID,
                    listRuleID: listRuleID
                )
                return SourceChapter(
                    id: [
                        source.id,
                        "video.v2.episode",
                        groupKey,
                        episodeKey
                    ].joined(separator: "::"),
                    title: episode.title,
                    subtitle: group.title,
                    url: episode.playURL,
                    isRestricted: episode.isRestricted,
                    isPaid: episode.isPaid,
                    navigationChapterURLs: navigationURLs,
                    navigationChapterTitles: navigationTitles,
                    navigationOrder: navigationOrder,
                    videoPlaybackHandoff: playbackHandoff
                )
            }
        }
    }

    private func requestLog(document: LoadedDocument) -> SourceRequestLog {
        return SourceRequestLog(
            url: document.requestURL,
            method: document.request?.method?.rawValue ?? "GET",
            headerCount: document.request?.headers?.count ?? 0,
            contentLength: document.response.content.utf8.count
        )
    }

    private func fallbackIssue(owner: String) -> SourceRuntimeIssue {
        return SourceRuntimeIssue(
            id: "video.v2.\(owner)FallbackUsed",
            severity: .info,
            message: "Video V2 \(owner) sourceStrategy used its fallback branch after the preferred branch returned a valid empty result."
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed: String? = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
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
