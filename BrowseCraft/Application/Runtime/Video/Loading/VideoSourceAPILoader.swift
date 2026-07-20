import Foundation
import BrowseCraftCore

struct VideoRuleAPIBranch<Value> {
    let value: Value
    let state: VideoRuleJSONPathState
    let requestLog: SourceRequestLog
    let extractionLog: SourceExtractionLog
    let finalURL: URL
}

// 中文注释：P1-5 API loader 沿用 PageContentLoader/JSONSerialization，只承载显式 Video V2 API 合同。
struct VideoSourceAPILoader {
    private struct LoadedJSON {
        let object: Any
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
        let loaded: LoadedJSON = try await self.loadJSON(
            source: source,
            rule: resolvedRule.raw,
            apiURLTemplate: api.url,
            baseRequest: entry.effectiveListAPIRequest,
            requestOverride: input.context.requestOverride,
            itemReference: nil,
            detailURL: nil,
            refererURL: refererURL,
            responsePolicy: api.responsePolicy,
            stage: .list,
            ownerDescription: "List API"
        )
        let resolution: VideoRuleJSONArrayResolution = VideoRuleJSONResolver.arrayResolution(
            at: api.itemPath,
            in: loaded.object
        )
        try self.validateArrayState(
            resolution.state,
            path: api.itemPath,
            owner: "List API",
            sourceID: source.id,
            stage: .list
        )
        guard resolution.state == .nonEmpty else {
            return VideoRuleAPIBranch(
                value: VideoRuleParsedList(items: [], candidateCount: 0, droppedCount: 0),
                state: .empty,
                requestLog: loaded.requestLog,
                extractionLog: SourceExtractionLog(
                    field: "list.api.item",
                    selector: api.itemPath,
                    candidateCount: 0,
                    outputCount: 0
                ),
                finalURL: loaded.response.finalURL
            )
        }

        let sortedObjects: [Any] = VideoRuleJSONResolver.sorted(
            resolution.values.enumerated().map { offset, value in
                return (
                    offset: offset,
                    value: value,
                    order: api.orderPath.flatMap { path in
                        return VideoRuleJSONResolver.doubleValue(
                            VideoRuleJSONResolver.firstJSONValue(at: path, in: value)
                        )
                    }
                )
            },
            sort: api.sort
        )
        var items: [VideoRuleParsedListItem] = []
        var seenDetailURLs: Set<String> = []
        for itemObject: Any in sortedObjects {
            guard let title: String = Self.nonEmpty(
                VideoRuleJSONResolver.stringValue(
                    VideoRuleJSONResolver.firstJSONValue(
                        at: api.fields.titlePath,
                        in: itemObject
                    )
                )
            ),
            let detailURL: URL = try self.listItemURL(
                api: api,
                source: source,
                rule: resolvedRule.raw,
                rootJSON: loaded.object,
                currentJSON: itemObject,
                baseURL: loaded.response.finalURL
            ),
            seenDetailURLs.insert(VideoRuleJSONResolver.canonicalURLKey(detailURL)).inserted else {
                continue
            }
            let idCode: String? = api.fields.idCodePath.flatMap { path in
                return Self.nonEmpty(
                    VideoRuleJSONResolver.stringValue(
                        VideoRuleJSONResolver.firstJSONValue(at: path, in: itemObject)
                    )
                )
            }
            let coverURL: URL? = try self.listCoverURL(
                api: api,
                source: source,
                rule: resolvedRule.raw,
                rootJSON: loaded.object,
                currentJSON: itemObject,
                baseURL: loaded.response.finalURL
            )
            let latestText: String? = api.fields.latestTextPath.flatMap { path in
                return Self.nonEmpty(
                    VideoRuleJSONResolver.stringValue(
                        VideoRuleJSONResolver.firstJSONValue(at: path, in: itemObject)
                    )
                )
            }
            items.append(
                VideoRuleParsedListItem(
                    idCode: idCode,
                    title: title,
                    detailURL: detailURL,
                    coverURL: coverURL,
                    latestText: latestText
                )
            )
        }
        guard items.isEmpty == false else {
            throw RuleExecutionError.responseContract(
                stage: .list,
                sourceID: source.id,
                reason: "List API itemPath \(api.itemPath) returned \(resolution.values.count) values, but all item mappings failed."
            )
        }
        let parsed = VideoRuleParsedList(
            items: items,
            candidateCount: resolution.values.count,
            droppedCount: resolution.values.count - items.count
        )
        return VideoRuleAPIBranch(
            value: parsed,
            state: .nonEmpty,
            requestLog: loaded.requestLog,
            extractionLog: SourceExtractionLog(
                field: "list.api.item",
                selector: api.itemPath,
                candidateCount: resolution.values.count,
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
        let loaded: LoadedJSON = try await self.loadJSON(
            source: source,
            rule: resolvedRule.raw,
            apiURLTemplate: api.url,
            baseRequest: entry.effectiveDetailAPIRequest,
            requestOverride: input.context.requestOverride ?? input.itemReference?.requestOverride,
            itemReference: input.itemReference,
            detailURL: input.detailURL,
            refererURL: input.detailURL,
            responsePolicy: api.responsePolicy,
            stage: .detail,
            ownerDescription: "Detail API"
        )
        let resolution: VideoRuleJSONObjectResolution = VideoRuleJSONResolver.objectResolution(
            at: api.itemPath,
            in: loaded.object
        )
        try self.validateObjectState(
            resolution.state,
            path: api.itemPath,
            owner: "Detail API",
            sourceID: source.id
        )
        guard resolution.state == .nonEmpty,
              let detailObject: [String: Any] = resolution.value else {
            let emptyDetail = VideoRuleParsedDetail(
                metadata: VideoRuleParsedDetailMetadata(
                    idCode: nil,
                    title: nil,
                    coverURL: nil,
                    description: nil,
                    attributes: []
                ),
                readyMatched: false
            )
            return VideoRuleAPIBranch(
                value: emptyDetail,
                state: .empty,
                requestLog: loaded.requestLog,
                extractionLog: SourceExtractionLog(
                    field: "detail.api.item",
                    selector: api.itemPath,
                    candidateCount: 0,
                    outputCount: 0
                ),
                finalURL: loaded.response.finalURL
            )
        }

        guard let title: String = Self.nonEmpty(
            VideoRuleJSONResolver.stringValue(
                VideoRuleJSONResolver.firstJSONValue(
                    at: api.fields.titlePath,
                    in: detailObject
                )
            )
        ) else {
            throw RuleExecutionError.responseContract(
                stage: .detail,
                sourceID: source.id,
                reason: "Detail API titlePath \(api.fields.titlePath) produced no title."
            )
        }
        let idCode: String? = api.fields.idCodePath.flatMap { path in
            return Self.nonEmpty(
                VideoRuleJSONResolver.stringValue(
                    VideoRuleJSONResolver.firstJSONValue(at: path, in: detailObject)
                )
            )
        }
        let coverURL: URL? = try self.detailCoverURL(
            api: api,
            source: source,
            rule: resolvedRule.raw,
            input: input,
            rootJSON: loaded.object,
            currentJSON: detailObject,
            baseURL: loaded.response.finalURL
        )
        let description: String? = api.fields.descriptionPath.flatMap { path in
            return Self.nonEmpty(
                VideoRuleJSONResolver.stringValue(
                    VideoRuleJSONResolver.firstJSONValue(at: path, in: detailObject)
                )
            )
        }
        let attributes: [VideoRuleParsedDetailAttribute] = (api.fields.metadata ?? []).compactMap { field in
            guard let value: String = Self.nonEmpty(
                VideoRuleJSONResolver.stringValue(
                    VideoRuleJSONResolver.firstJSONValue(at: field.valuePath, in: detailObject)
                )
            ) else {
                return nil
            }
            return VideoRuleParsedDetailAttribute(
                id: field.id,
                label: Self.nonEmpty(field.label),
                value: value
            )
        }
        let parsed = VideoRuleParsedDetail(
            metadata: VideoRuleParsedDetailMetadata(
                idCode: idCode,
                title: title,
                coverURL: coverURL,
                description: description,
                attributes: attributes
            ),
            readyMatched: true
        )
        return VideoRuleAPIBranch(
            value: parsed,
            state: .nonEmpty,
            requestLog: loaded.requestLog,
            extractionLog: SourceExtractionLog(
                field: "detail.api.item",
                selector: api.itemPath,
                candidateCount: 1,
                outputCount: 1
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
        let loaded: LoadedJSON = try await self.loadJSON(
            source: source,
            rule: resolvedRule.raw,
            apiURLTemplate: api.url,
            baseRequest: entry.effectiveEpisodeAPIRequest,
            requestOverride: input.context.requestOverride ?? input.itemReference?.requestOverride,
            itemReference: input.itemReference,
            detailURL: input.detailURL,
            refererURL: input.detailURL,
            responsePolicy: api.responsePolicy,
            stage: .detail,
            ownerDescription: "Episode API"
        )

        let groupObjects: [Any]
        if let groupPath: String = api.groupPath {
            let resolution: VideoRuleJSONArrayResolution = VideoRuleJSONResolver.arrayResolution(
                at: groupPath,
                in: loaded.object
            )
            try self.validateArrayState(
                resolution.state,
                path: groupPath,
                owner: "Episode API groupPath",
                sourceID: source.id,
                stage: .detail
            )
            if resolution.state == .empty {
                return self.emptyEpisodesBranch(
                    requestLog: loaded.requestLog,
                    finalURL: loaded.response.finalURL,
                    selector: groupPath
                )
            }
            groupObjects = resolution.values
        } else {
            groupObjects = [loaded.object]
        }

        var groups: [VideoRuleParsedEpisodeGroup] = []
        var totalCandidates: Int = 0
        var totalDropped: Int = 0
        for groupObject: Any in groupObjects {
            let itemResolution: VideoRuleJSONArrayResolution = VideoRuleJSONResolver.arrayResolution(
                at: api.itemPath,
                in: groupObject
            )
            try self.validateArrayState(
                itemResolution.state,
                path: api.itemPath,
                owner: "Episode API itemPath",
                sourceID: source.id,
                stage: .detail
            )
            let groupIDCode: String? = api.groupFields?.idCodePath.flatMap { path in
                return Self.nonEmpty(
                    VideoRuleJSONResolver.stringValue(
                        VideoRuleJSONResolver.firstJSONValue(at: path, in: groupObject)
                    )
                )
            }
            let groupTitle: String? = api.groupFields?.titlePath.flatMap { path in
                return Self.nonEmpty(
                    VideoRuleJSONResolver.stringValue(
                        VideoRuleJSONResolver.firstJSONValue(at: path, in: groupObject)
                    )
                )
            }
            let sortedObjects: [Any] = VideoRuleJSONResolver.sorted(
                itemResolution.values.enumerated().map { offset, value in
                    return (
                        offset: offset,
                        value: value,
                        order: api.fields.orderPath.flatMap { path in
                            return VideoRuleJSONResolver.doubleValue(
                                VideoRuleJSONResolver.firstJSONValue(at: path, in: value)
                            )
                        }
                    )
                },
                sort: api.sort
            )
            var episodes: [VideoRuleParsedEpisode] = []
            var seenPlayURLs: Set<String> = []
            for itemObject: Any in sortedObjects {
                guard let title: String = Self.nonEmpty(
                    VideoRuleJSONResolver.stringValue(
                        VideoRuleJSONResolver.firstJSONValue(
                            at: api.fields.titlePath,
                            in: itemObject
                        )
                    )
                ),
                let playURL: URL = try self.episodePlayURL(
                    api: api,
                    source: source,
                    rule: resolvedRule.raw,
                    input: input,
                    rootJSON: loaded.object,
                    groupJSON: api.groupPath == nil ? nil : groupObject,
                    currentJSON: itemObject,
                    baseURL: loaded.response.finalURL
                ),
                seenPlayURLs.insert(VideoRuleJSONResolver.canonicalURLKey(playURL)).inserted else {
                    continue
                }
                let idCode: String? = api.fields.idCodePath.flatMap { path in
                    return Self.nonEmpty(
                        VideoRuleJSONResolver.stringValue(
                            VideoRuleJSONResolver.firstJSONValue(at: path, in: itemObject)
                        )
                    )
                }
                episodes.append(
                    VideoRuleParsedEpisode(
                        idCode: idCode,
                        title: title,
                        playURL: playURL,
                        order: api.fields.orderPath.flatMap { path in
                            return VideoRuleJSONResolver.doubleValue(
                                VideoRuleJSONResolver.firstJSONValue(at: path, in: itemObject)
                            )
                        },
                        isRestricted: self.scalarMatch(
                            path: api.fields.restrictionPath,
                            values: api.fields.restrictedValues,
                            object: itemObject
                        ),
                        isPaid: self.scalarMatch(
                            path: api.fields.paidPath,
                            values: api.fields.paidValues,
                            object: itemObject
                        )
                    )
                )
            }
            totalCandidates += itemResolution.values.count
            totalDropped += itemResolution.values.count - episodes.count
            groups.append(
                VideoRuleParsedEpisodeGroup(
                    idCode: groupIDCode,
                    title: groupTitle,
                    episodes: episodes,
                    candidateCount: itemResolution.values.count,
                    droppedCount: itemResolution.values.count - episodes.count
                )
            )
        }

        if totalCandidates == 0 {
            return self.emptyEpisodesBranch(
                requestLog: loaded.requestLog,
                finalURL: loaded.response.finalURL,
                selector: api.itemPath
            )
        }
        guard groups.flatMap(\.episodes).isEmpty == false else {
            throw RuleExecutionError.responseContract(
                stage: .detail,
                sourceID: source.id,
                reason: "Episode API itemPath \(api.itemPath) returned \(totalCandidates) values, but all item mappings failed."
            )
        }
        let parsed = VideoRuleParsedEpisodes(
            groups: groups,
            readyMatched: true,
            candidateCount: totalCandidates,
            droppedCount: totalDropped
        )
        return VideoRuleAPIBranch(
            value: parsed,
            state: .nonEmpty,
            requestLog: loaded.requestLog,
            extractionLog: SourceExtractionLog(
                field: "episode.api.item",
                selector: api.itemPath,
                candidateCount: totalCandidates,
                outputCount: parsed.episodes.count
            ),
            finalURL: loaded.response.finalURL
        )
    }

    private func loadJSON(
        source: Source,
        rule: VideoSiteRule,
        apiURLTemplate: String,
        baseRequest: RequestConfig?,
        requestOverride: SourceRequestOverride?,
        itemReference: SourceItemReference?,
        detailURL: URL?,
        refererURL: URL,
        responsePolicy: APIResponsePolicy,
        stage: RuleExecutionLogger.Stage,
        ownerDescription: String
    ) async throws -> LoadedJSON {
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
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(
                with: Data(response.content.utf8),
                options: [.fragmentsAllowed]
            )
        } catch {
            throw RuleExecutionError.responseContract(
                stage: stage,
                sourceID: source.id,
                reason: "\(ownerDescription) returned invalid JSON; shape=\(Self.jsonShape(response.content)) bytes=\(response.content.utf8.count)."
            )
        }
        switch VideoRuleAPIResponseEvaluator.evaluate(json: jsonObject, policy: responsePolicy) {
        case .allowParsing:
            break
        case .businessFailure(let message):
            throw RuleExecutionError.sourceAPI(
                stage: stage,
                sourceID: source.id,
                reason: "\(ownerDescription) returned business failure: \(message)"
            )
        }
        return LoadedJSON(
            object: jsonObject,
            response: response,
            requestLog: SourceRequestLog(
                url: apiURL,
                method: request?.method?.rawValue ?? "GET",
                headerCount: request?.headers?.count ?? 0,
                contentLength: response.content.utf8.count
            )
        )
    }

    private func validateArrayState(
        _ state: VideoRuleJSONPathState,
        path: String,
        owner: String,
        sourceID: String,
        stage: RuleExecutionLogger.Stage
    ) throws {
        guard state == .empty || state == .nonEmpty else {
            throw RuleExecutionError.responseContract(
                stage: stage,
                sourceID: sourceID,
                reason: "\(owner) path \(path) resolved as \(state.rawValue)."
            )
        }
    }

    private func validateObjectState(
        _ state: VideoRuleJSONPathState,
        path: String,
        owner: String,
        sourceID: String
    ) throws {
        guard state == .empty || state == .nonEmpty else {
            throw RuleExecutionError.responseContract(
                stage: .detail,
                sourceID: sourceID,
                reason: "\(owner) path \(path) resolved as \(state.rawValue)."
            )
        }
    }

    private func listItemURL(
        api: VideoListAPIRule,
        source: Source,
        rule: VideoSiteRule,
        rootJSON: Any,
        currentJSON: Any,
        baseURL: URL
    ) throws -> URL? {
        let rawValue: String?
        if let template: String = api.fields.detailURLTemplate {
            rawValue = try self.resolveOutputTemplate(
                template,
                source: source,
                rule: rule,
                rootJSON: rootJSON,
                currentJSON: currentJSON,
                groupJSON: nil,
                itemReference: nil,
                detailURL: nil,
                stage: .list
            )
        } else {
            rawValue = api.fields.detailURLPath.flatMap { path in
                return VideoRuleJSONResolver.stringValue(
                    VideoRuleJSONResolver.firstJSONValue(at: path, in: currentJSON)
                )
            }
        }
        return VideoRuleJSONResolver.absoluteHTTPURL(rawValue, relativeTo: baseURL)
    }

    private func listCoverURL(
        api: VideoListAPIRule,
        source: Source,
        rule: VideoSiteRule,
        rootJSON: Any,
        currentJSON: Any,
        baseURL: URL
    ) throws -> URL? {
        let rawValue: String?
        if let template: String = api.fields.coverTemplate {
            rawValue = try self.resolveOutputTemplate(
                template,
                source: source,
                rule: rule,
                rootJSON: rootJSON,
                currentJSON: currentJSON,
                groupJSON: nil,
                itemReference: nil,
                detailURL: nil,
                stage: .list
            )
        } else {
            rawValue = api.fields.coverPath.flatMap { path in
                return VideoRuleJSONResolver.stringValue(
                    VideoRuleJSONResolver.firstJSONValue(at: path, in: currentJSON)
                )
            }
        }
        return VideoRuleJSONResolver.absoluteHTTPURL(rawValue, relativeTo: baseURL)
    }

    private func detailCoverURL(
        api: VideoDetailAPIRule,
        source: Source,
        rule: VideoSiteRule,
        input: SourceDetailInput,
        rootJSON: Any,
        currentJSON: Any,
        baseURL: URL
    ) throws -> URL? {
        let rawValue: String?
        if let template: String = api.fields.coverTemplate {
            rawValue = try self.resolveOutputTemplate(
                template,
                source: source,
                rule: rule,
                rootJSON: rootJSON,
                currentJSON: currentJSON,
                groupJSON: nil,
                itemReference: input.itemReference,
                detailURL: input.detailURL,
                stage: .detail
            )
        } else {
            rawValue = api.fields.coverPath.flatMap { path in
                return VideoRuleJSONResolver.stringValue(
                    VideoRuleJSONResolver.firstJSONValue(at: path, in: currentJSON)
                )
            }
        }
        return VideoRuleJSONResolver.absoluteHTTPURL(rawValue, relativeTo: baseURL)
    }

    private func episodePlayURL(
        api: VideoEpisodeAPIRule,
        source: Source,
        rule: VideoSiteRule,
        input: SourceDetailInput,
        rootJSON: Any,
        groupJSON: Any?,
        currentJSON: Any,
        baseURL: URL
    ) throws -> URL? {
        let rawValue: String?
        if let template: String = api.fields.playURLTemplate {
            rawValue = try self.resolveOutputTemplate(
                template,
                source: source,
                rule: rule,
                rootJSON: rootJSON,
                currentJSON: currentJSON,
                groupJSON: groupJSON,
                itemReference: input.itemReference,
                detailURL: input.detailURL,
                stage: .detail
            )
        } else {
            rawValue = api.fields.playURLPath.flatMap { path in
                return VideoRuleJSONResolver.stringValue(
                    VideoRuleJSONResolver.firstJSONValue(at: path, in: currentJSON)
                )
            }
        }
        return VideoRuleJSONResolver.absoluteHTTPURL(rawValue, relativeTo: baseURL)
    }

    private func scalarMatch(
        path: String?,
        values: [APIResponseScalar]?,
        object: Any
    ) -> Bool? {
        guard let path: String,
              let scalar: APIResponseScalar = VideoRuleJSONResolver.responseScalar(
                VideoRuleJSONResolver.firstJSONValue(at: path, in: object)
              ) else {
            return nil
        }
        return (values ?? []).contains(scalar)
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

    private func resolveOutputTemplate(
        _ template: String,
        source: Source,
        rule: VideoSiteRule,
        rootJSON: Any,
        currentJSON: Any,
        groupJSON: Any?,
        itemReference: SourceItemReference?,
        detailURL: URL?,
        stage: RuleExecutionLogger.Stage
    ) throws -> String {
        do {
            return try VideoRuleAPITemplateResolver.resolveTemplate(
                template,
                context: VideoRuleAPITemplateContext(
                    source: source,
                    rule: rule,
                    itemReference: itemReference,
                    detailURL: detailURL,
                    rootJSON: rootJSON,
                    currentJSON: currentJSON,
                    groupJSON: groupJSON,
                    credentialProvider: self.credentialProvider
                )
            )
        } catch {
            throw RuleExecutionError.ruleConfiguration(
                stage: stage,
                sourceID: source.id,
                reason: error.localizedDescription
            )
        }
    }

    private func emptyEpisodesBranch(
        requestLog: SourceRequestLog,
        finalURL: URL,
        selector: String
    ) -> VideoRuleAPIBranch<VideoRuleParsedEpisodes> {
        return VideoRuleAPIBranch(
            value: VideoRuleParsedEpisodes(
                groups: [],
                readyMatched: false,
                candidateCount: 0,
                droppedCount: 0
            ),
            state: .empty,
            requestLog: requestLog,
            extractionLog: SourceExtractionLog(
                field: "episode.api.item",
                selector: selector,
                candidateCount: 0,
                outputCount: 0
            ),
            finalURL: finalURL
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let normalized: String? = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }

    private static func jsonShape(_ value: String) -> String {
        let normalized: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("{") {
            return "object-like"
        }
        if normalized.hasPrefix("[") {
            return "array-like"
        }
        if normalized.hasPrefix("<") {
            return "html-like"
        }
        return "scalar-or-text"
    }
}
