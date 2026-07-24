import Foundation
import BrowseCraftCore

enum VideoRuleBranchState {
    case empty
    case nonEmpty
}

struct VideoRuleAPIBranch<Value> {
    let value: Value
    let state: VideoRuleBranchState
    let requestLog: SourceRequestLog
    let extractionLog: SourceExtractionLog
    let finalURL: URL
}

// 中文注释：API loader 只负责请求与传输；list/detail/episode API 响应解释
// 全部由 BrowseCraftCore 执行。
struct VideoSourceAPILoader {
    private struct LoadedResponse {
        let response: PageContentResponse
        let requestLog: SourceRequestLog
    }

    private let pageContentLoader: PageContentLoader
    private let sourceRequestOverrideResolver: SourceRequestOverrideResolver
    private let credentialProvider: any SourceCredentialProviding

    init(
        pageContentLoader: PageContentLoader,
        sourceRequestOverrideResolver: SourceRequestOverrideResolver = SourceRequestOverrideResolver(),
        credentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider()
    ) {
        self.pageContentLoader = pageContentLoader
        self.sourceRequestOverrideResolver = sourceRequestOverrideResolver
        self.credentialProvider = credentialProvider
    }

    func loadList(
        source: Source,
        resolvedRule: ResolvedVideoSiteRule,
        entry: ResolvedVideoListEntry,
        rule: VideoListRule,
        input: SourceListInput,
        refererURL: URL
    ) async throws -> VideoRuleAPIBranch<VideoRuleParsedList> {
        guard let api: VideoListAPIRule = rule.listAPI else {
            throw SourceRuntimeError.invalidInput(
                "Video V2 list rule \(rule.id) has no listAPI."
            )
        }
        let loaded: LoadedResponse = try await self.loadResponse(
            source: source,
            rule: resolvedRule.raw,
            apiURLTemplate: api.url,
            baseRequest: entry.effectiveListAPIRequest,
            requestOverride: input.context.requestOverride,
            itemReference: nil,
            detailURL: nil,
            refererURL: refererURL,
            stage: .list,
            ownerDescription: "List API"
        )
        let contextValues = VideoRuleAPITemplateResolver.resolvedContextValues(
            source: source,
            rule: resolvedRule.raw,
            credentialProvider: self.credentialProvider
        ).mapValues(BrowseCraftCore.SourceRuntimeValue.string)
        let output: SourceListOutput
        do {
            output = try BrowseCraftCore.DefaultVideoListRuleParser()
                .parseListAPIResponse(
                    BrowseCraftCore.VideoListAPIResponseParsingInput(
                        document: BrowseCraftCore.SourceContentDocument(
                            text: loaded.response.content,
                            finalURL: loaded.response.finalURL,
                            format: .json,
                            mediaType: "application/json"
                        ),
                        rule: api,
                        sourceBaseURL: URL(string: source.baseURL),
                        contextValues: contextValues,
                        runtimeContext: input.context
                    )
                )
        } catch {
            throw self.apiParsingError(
                error,
                sourceID: source.id,
                stage: .list,
                owner: "List"
            )
        }
        let items = output.items.compactMap { item -> VideoRuleParsedListItem? in
            guard let detailURL = item.detailURL else {
                return nil
            }
            return VideoRuleParsedListItem(
                idCode: item.idCode,
                title: item.title,
                detailURL: detailURL,
                coverURL: item.coverURL,
                latestText: item.latestText
            )
        }
        let candidateCount = output.diagnostics.candidateSummary?
            .totalCandidates ?? items.count
        let droppedCount = output.diagnostics.candidateSummary?
            .warningCount ?? 0
        let parsed = VideoRuleParsedList(
            items: items,
            candidateCount: candidateCount,
            droppedCount: droppedCount
        )
        return VideoRuleAPIBranch(
            value: parsed,
            state: candidateCount == 0 ? .empty : .nonEmpty,
            requestLog: loaded.requestLog,
            extractionLog: output.diagnostics.extractionLogs.first
                ?? SourceExtractionLog(
                    field: "list.api.item",
                    selector: api.itemPath,
                    candidateCount: candidateCount,
                    outputCount: items.count
                ),
            finalURL: loaded.response.finalURL
        )
    }

    func loadDetail(
        source: Source,
        resolvedRule: ResolvedVideoSiteRule,
        entry: ResolvedVideoDetailEntry,
        rule: VideoDetailRule,
        input: SourceDetailInput
    ) async throws -> VideoRuleAPIBranch<VideoRuleParsedDetail> {
        guard let api: VideoDetailAPIRule = rule.detailAPI else {
            throw SourceRuntimeError.invalidInput(
                "Video V2 detail rule \(rule.id) has no detailAPI."
            )
        }
        let loaded: LoadedResponse = try await self.loadResponse(
            source: source,
            rule: resolvedRule.raw,
            apiURLTemplate: api.url,
            baseRequest: entry.effectiveDetailAPIRequest,
            requestOverride: input.context.requestOverride ?? input.itemReference?.requestOverride,
            itemReference: input.itemReference,
            detailURL: input.detailURL,
            refererURL: input.detailURL,
            stage: .detail,
            ownerDescription: "Detail API"
        )
        let contextValues = VideoRuleAPITemplateResolver.resolvedContextValues(
            source: source,
            rule: resolvedRule.raw,
            credentialProvider: self.credentialProvider
        ).mapValues(BrowseCraftCore.SourceRuntimeValue.string)
        let output: BrowseCraftCore.VideoDetailParsingResult
        do {
            output = try BrowseCraftCore.DefaultVideoDetailRuleParser()
                .parseDetailAPIResponse(
                    BrowseCraftCore.VideoDetailAPIResponseParsingInput(
                        document: BrowseCraftCore.SourceContentDocument(
                            text: loaded.response.content,
                            finalURL: loaded.response.finalURL,
                            format: .json,
                            mediaType: "application/json"
                        ),
                        rule: api,
                        sourceBaseURL: URL(string: source.baseURL),
                        contextValues: contextValues,
                        itemReference: input.itemReference,
                        detailURL: input.detailURL,
                        runtimeContext: input.context
                    )
                )
        } catch {
            throw self.apiParsingError(
                error,
                sourceID: source.id,
                stage: .detail,
                owner: "Detail"
            )
        }
        let attributes = output.metadata.attributes.enumerated().map { offset, attribute in
            VideoRuleParsedDetailAttribute(
                id: attribute.label ?? "metadata-\(offset)",
                label: attribute.label,
                value: attribute.value
            )
        }
        let parsed = VideoRuleParsedDetail(
            metadata: VideoRuleParsedDetailMetadata(
                idCode: output.metadata.idCode,
                title: output.metadata.title,
                coverURL: output.metadata.coverURL,
                description: output.metadata.description,
                attributes: attributes
            ),
            readyMatched: output.readyMatched
        )
        return VideoRuleAPIBranch(
            value: parsed,
            state: output.readyMatched ? .nonEmpty : .empty,
            requestLog: loaded.requestLog,
            extractionLog: output.diagnostics.extractionLogs.first
                ?? SourceExtractionLog(
                    field: "detail.api.item",
                    selector: api.itemPath,
                    candidateCount: output.readyMatched ? 1 : 0,
                    outputCount: output.readyMatched ? 1 : 0
                ),
            finalURL: loaded.response.finalURL
        )
    }

    func loadEpisodes(
        source: Source,
        resolvedRule: ResolvedVideoSiteRule,
        entry: ResolvedVideoDetailEntry,
        rule: VideoEpisodeRule,
        input: SourceDetailInput
    ) async throws -> VideoRuleAPIBranch<VideoRuleParsedEpisodes> {
        guard let api: VideoEpisodeAPIRule = rule.episodeAPI else {
            throw SourceRuntimeError.invalidInput(
                "Video V2 episode rule \(rule.id) has no episodeAPI."
            )
        }
        let loaded: LoadedResponse = try await self.loadResponse(
            source: source,
            rule: resolvedRule.raw,
            apiURLTemplate: api.url,
            baseRequest: entry.effectiveEpisodeAPIRequest,
            requestOverride: input.context.requestOverride ?? input.itemReference?.requestOverride,
            itemReference: input.itemReference,
            detailURL: input.detailURL,
            refererURL: input.detailURL,
            stage: .detail,
            ownerDescription: "Episode API"
        )
        let contextValues = VideoRuleAPITemplateResolver.resolvedContextValues(
            source: source,
            rule: resolvedRule.raw,
            credentialProvider: self.credentialProvider
        ).mapValues(BrowseCraftCore.SourceRuntimeValue.string)
        let output: BrowseCraftCore.VideoEpisodeParsingResult
        do {
            output = try BrowseCraftCore.DefaultVideoEpisodeRuleParser()
                .parseEpisodeAPIResponse(
                    BrowseCraftCore.VideoEpisodeAPIResponseParsingInput(
                        document: BrowseCraftCore.SourceContentDocument(
                            text: loaded.response.content,
                            finalURL: loaded.response.finalURL,
                            format: .json,
                            mediaType: "application/json"
                        ),
                        rule: api,
                        sourceBaseURL: URL(string: source.baseURL),
                        contextValues: contextValues,
                        itemReference: input.itemReference,
                        detailURL: input.detailURL,
                        runtimeContext: input.context
                    )
                )
        } catch {
            throw self.apiParsingError(
                error,
                sourceID: source.id,
                stage: .detail,
                owner: "Episode"
            )
        }
        let parsed = CoreVideoRuleSourceParser.episodes(from: output)
        return VideoRuleAPIBranch(
            value: parsed,
            state: output.readyMatched ? .nonEmpty : .empty,
            requestLog: loaded.requestLog,
            extractionLog: output.diagnostics.extractionLogs.first
                ?? SourceExtractionLog(
                    field: "episode.api.item",
                    selector: api.itemPath,
                    candidateCount: parsed.candidateCount,
                    outputCount: parsed.episodes.count
                ),
            finalURL: loaded.response.finalURL
        )
    }

    private func loadResponse(
        source: Source,
        rule: VideoSiteRule,
        apiURLTemplate: String,
        baseRequest: RequestConfig?,
        requestOverride: SourceRequestOverride?,
        itemReference: SourceItemReference?,
        detailURL: URL?,
        refererURL: URL,
        stage: RuleExecutionLogger.Stage,
        ownerDescription: String
    ) async throws -> LoadedResponse {
        let templateContext = VideoRuleAPITemplateContext(
            source: source,
            rule: rule,
            itemReference: itemReference,
            detailURL: detailURL,
            credentialProvider: self.credentialProvider
        )
        let apiURLString: String
        let request: RequestConfig?
        do {
            apiURLString = try VideoRuleAPITemplateResolver.resolveTemplate(
                apiURLTemplate,
                context: templateContext
            )
            let mergedRequest: RequestConfig? = self.sourceRequestOverrideResolver.resolve(
                base: baseRequest,
                override: requestOverride
            )
            request = try VideoRuleAPITemplateResolver.resolvedRequest(
                mergedRequest,
                context: templateContext
            )
        } catch {
            throw RuleExecutionError.ruleConfiguration(
                stage: stage,
                sourceID: source.id,
                reason: error.localizedDescription
            )
        }
        guard let apiURL: URL = self.declaredAPIURL(apiURLString) else {
            throw RuleExecutionError.ruleConfiguration(
                stage: stage,
                sourceID: source.id,
                reason: "\(ownerDescription) URL is invalid: \(apiURLString)"
            )
        }
        let response: PageContentResponse = try await self.pageContentLoader.loadContent(
            PageLoadRequest(
                url: apiURL,
                requestConfig: request,
                sourceContext: SourceRequestContext(
                    sourceID: source.id,
                    baseURL: URL(string: source.baseURL),
                    purpose: .video,
                    refererURL: refererURL
                )
            )
        )
        return LoadedResponse(
            response: response,
            requestLog: SourceRequestLog(
                url: apiURL,
                method: request?.method?.rawValue ?? "GET",
                headerCount: request?.headers?.count ?? 0,
                contentLength: response.content.utf8.count
            )
        )
    }

    private func apiParsingError(
        _ error: Error,
        sourceID: String,
        stage: RuleExecutionLogger.Stage,
        owner: String
    ) -> RuleExecutionError {
        guard let parsingError = error as? BrowseCraftCore.SourceParsingError else {
            return .unknown(underlyingDescription: error.localizedDescription)
        }
        switch parsingError {
        case .responseContract(let reason):
            if reason.contains("\(owner) API returned error:") {
                return .sourceAPI(
                    stage: stage,
                    sourceID: sourceID,
                    reason: reason
                )
            }
            return .responseContract(
                stage: stage,
                sourceID: sourceID,
                reason: reason
            )
        case .invalidInput, .incompleteRule:
            return .ruleConfiguration(
                stage: stage,
                sourceID: sourceID,
                reason: parsingError.localizedDescription
            )
        default:
            return .responseContract(
                stage: stage,
                sourceID: sourceID,
                reason: parsingError.localizedDescription
            )
        }
    }

    private func declaredAPIURL(_ rawValue: String) -> URL? {
        guard let url: URL = URL(string: rawValue),
              let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

}
