import Foundation
import BrowseCraftCore

// 中文注释：P2-4 playback loader 固定执行 direct media → iframe → 显式 WebUI fallback；不调用 legacy mapper。
struct VideoSourcePlaybackLoader {
    private let pageContentLoader: PageContentLoader
    private let parser: VideoRuleSourceParsingService
    private let renderGuard: VideoHTMLRenderGuard
    private let sourceRequestOverrideResolver: SourceRequestOverrideResolver
    private let credentialProvider: any SourceCredentialProviding
    private let templateResolver: BrowseCraftCore.VideoPlaybackTemplateResolver

    init(
        pageContentLoader: PageContentLoader,
        parser: VideoRuleSourceParsingService,
        renderGuard: VideoHTMLRenderGuard = VideoHTMLRenderGuard(),
        sourceRequestOverrideResolver: SourceRequestOverrideResolver = SourceRequestOverrideResolver(),
        credentialProvider: any SourceCredentialProviding = EmptySourceCredentialProvider(),
        templateResolver: BrowseCraftCore.VideoPlaybackTemplateResolver = .init()
    ) {
        self.pageContentLoader = pageContentLoader
        self.parser = parser
        self.renderGuard = renderGuard
        self.sourceRequestOverrideResolver = sourceRequestOverrideResolver
        self.credentialProvider = credentialProvider
        self.templateResolver = templateResolver
    }

    func execute(
        source: Source,
        resolvedRule: ResolvedVideoSiteRule,
        input: SourceVideoPlaybackInput
    ) async throws -> SourceVideoPlaybackOutput {
        let session: VideoPreparedPlaybackExecutionSession = try self.prepare(
            source: source,
            resolvedRule: resolvedRule,
            input: input
        )
        return try await self.execute(session)
    }

    // 中文注释：只在这里解析 handoff、owner、request 与规则；后续 audit 不得重复物化第二份执行状态。
    func prepare(
        source: Source,
        resolvedRule: ResolvedVideoSiteRule,
        input: SourceVideoPlaybackInput
    ) throws -> VideoPreparedPlaybackExecutionSession {
        let handoff: SourceVideoPlaybackHandoff = try self.handoff(input)
        let entry: ResolvedVideoPlaybackEntry = try self.entry(
            input: input,
            handoff: handoff,
            resolvedRule: resolvedRule
        )
        let playbackRule: VideoPlaybackRule = resolvedRule.playbackRule(for: entry)
        let requestURL: URL = try self.requestURL(input)
        let mergedRequest: RequestConfig? = self.sourceRequestOverrideResolver.resolve(
            base: entry.effectivePlaybackRequest,
            override: input.context.requestOverride
        )
        let request: RequestConfig?
        do {
            request = try VideoRuleAPITemplateResolver.resolvedRequest(
                mergedRequest,
                context: VideoRuleAPITemplateContext(
                    source: source,
                    rule: resolvedRule.raw,
                    credentialProvider: self.credentialProvider
                )
            )
        } catch {
            throw RuleExecutionError.ruleConfiguration(
                stage: .playback,
                sourceID: source.id,
                reason: error.localizedDescription
            )
        }
        return VideoPreparedPlaybackExecutionSession(
            source: source,
            input: input,
            siteRule: resolvedRule.raw,
            handoff: handoff,
            entry: entry,
            playbackRule: playbackRule,
            detailReadyDeclared: resolvedRule.detailRule(for: entry).ready != nil,
            requestURL: requestURL,
            request: request
        )
    }

    func execute(
        _ session: VideoPreparedPlaybackExecutionSession
    ) async throws -> SourceVideoPlaybackOutput {
        return try await self.executeWithRouteFacts(session).output
    }

    // 中文注释：routeFacts 只保留本次内存中的前置路线事实；普通播放输出不会持久化 URL 或把它升级为 runtime evidence。
    func executeWithRouteFacts(
        _ session: VideoPreparedPlaybackExecutionSession
    ) async throws -> VideoPreparedPlaybackExecutionResult {
        let source: Source = session.source
        let input: SourceVideoPlaybackInput = session.input
        let handoff: SourceVideoPlaybackHandoff = session.handoff
        let playbackRule: VideoPlaybackRule = session.playbackRule
        let requestURL: URL = session.requestURL
        let request: RequestConfig? = session.request

        var currentURL: URL = requestURL
        var refererURL: URL = requestURL
        var rootFinalURL: URL?
        var lastResponseFinalURL: URL?
        var depth: Int = 0
        var visitedURLKeys: Set<String> = [self.canonicalURLKey(requestURL)]
        var resolvingIframeRoute: Bool = false
        var iframeActivationURL: URL?
        var selectedRouteSlot: VideoRuntimeEvidenceRouteSlot?
        var routeFactsBySlot: [VideoRuntimeEvidenceRouteSlot: VideoPreparedPlaybackRouteFact] = [:]
        var knownEncryptedMediaFingerprints: Set<VideoRuntimeEvidenceFingerprint> = []
        var hasUnidentifiedKnownEncryptedMedia: Bool = false
        var requestLogs: [SourceRequestLog] = []
        var extractionLogs: [SourceExtractionLog] = []
        var issues: [SourceRuntimeIssue] = []
        var candidateMediaURL: URL?
        var candidateMediaKind: SourceVideoMediaKind = .unknown
        var playbackRequestConfig: SourcePlaybackRequestConfig?
        var status: SourceVideoPlaybackStatus = .failed(.mediaURLNotFound)

        playbackLoop: while true {
            let response: PageContentResponse = try await self.pageContentLoader.loadContent(
                PageLoadRequest(
                    url: currentURL,
                    requestConfig: request,
                    sourceContext: SourceRequestContext(
                        sourceID: source.id,
                        baseURL: URL(string: source.baseURL),
                        purpose: .video,
                        refererURL: refererURL
                    )
                )
            )
            rootFinalURL = rootFinalURL ?? response.finalURL
            lastResponseFinalURL = response.finalURL
            issues += try self.renderGuard.validateMappableHTML(
                url: response.finalURL,
                html: response.content,
                request: request
            )
            let parsed: VideoRuleParsedPlayback
            do {
                parsed = try self.parser.parsePlayback(
                    html: response.content,
                    pageURL: response.finalURL,
                    rule: playbackRule
                )
            } catch {
                throw RuleExecutionError.parserDiagnostics(
                    stage: .playback,
                    sourceID: source.id,
                    ruleID: playbackRule.id,
                    url: self.safeLogURL(response.finalURL).absoluteString,
                    operation: "parseVideoV2Playback",
                    selector: self.playbackSelector(playbackRule),
                    htmlPreview: Self.htmlPreview(from: response.content),
                    underlyingDescription: error.localizedDescription
                )
            }

            let requestLogURL: URL = self.safeLogURL(response.finalURL)
            requestLogs.append(
                SourceRequestLog(
                    url: requestLogURL,
                    method: request?.method?.rawValue ?? "GET",
                    headerCount: request?.headers?.count ?? 0,
                    contentLength: response.content.utf8.count
                )
            )
            if playbackRule.effectiveMediaCandidates.isEmpty == false {
                extractionLogs.append(
                    SourceExtractionLog(
                        field: "playback.dom.media.depth\(depth)",
                        selector: self.playbackSelector(playbackRule),
                        candidateCount: parsed.mediaCandidateCount,
                        outputCount: parsed.mediaCandidates.count
                    )
                )
            }
            if let iframeRule: VideoIframePlaybackRule = playbackRule.iframe {
                extractionLogs.append(
                    SourceExtractionLog(
                        field: "playback.dom.iframe.depth\(depth)",
                        selector: iframeRule.url.selector,
                        candidateCount: parsed.iframeCandidateCount,
                        outputCount: parsed.iframeURLs.count
                    )
                )
            }

            try self.validateParsedPlayback(parsed, rule: playbackRule, sourceID: source.id)

            let mediaCandidate: VideoRuleParsedMediaCandidate? = parsed.mediaCandidates.first

            if resolvingIframeRoute {
                if let mediaCandidate, mediaCandidate.kind == .mp4 {
                    if self.isIndependentFromKnownEncryptedMedia(
                        kind: .mp4,
                        url: mediaCandidate.url,
                        knownFingerprints: knownEncryptedMediaFingerprints,
                        hasUnidentifiedKnownEncryptedMedia: hasUnidentifiedKnownEncryptedMedia
                    ) {
                        candidateMediaURL = mediaCandidate.url
                        candidateMediaKind = .mp4
                        playbackRequestConfig = try self.playbackRequest(
                            source: source,
                            rule: session.siteRule,
                            mediaRequest: playbackRule.mediaRequest,
                            finalURL: response.finalURL
                        )
                        status = .playable
                        selectedRouteSlot = .iframe
                        routeFactsBySlot[.iframe] = VideoPreparedPlaybackRouteFact(
                            routeSlot: .iframe,
                            executionMode: .iframeResolve,
                            disposition: .selectedForPlayer,
                            routeActivationURL: iframeActivationURL,
                            candidateMediaURL: mediaCandidate.url,
                            candidateMediaKind: .mp4,
                            reason: nil
                        )
                    } else {
                        status = .failed(.unsupportedMediaKind)
                        routeFactsBySlot[.iframe] = VideoPreparedPlaybackRouteFact(
                            routeSlot: .iframe,
                            executionMode: .iframeResolve,
                            disposition: .rejectedBeforePlayer,
                            routeActivationURL: iframeActivationURL,
                            candidateMediaURL: mediaCandidate.url,
                            candidateMediaKind: .mp4,
                            reason: .knownEncryptedMedia
                        )
                    }
                    break playbackLoop
                }

                if let mediaCandidate {
                    let resolvedPlaybackRequest: SourcePlaybackRequestConfig? = try self.playbackRequest(
                        source: source,
                        rule: session.siteRule,
                        mediaRequest: playbackRule.mediaRequest,
                        finalURL: response.finalURL
                    )
                    let mediaFingerprint: VideoRuntimeEvidenceFingerprint? = self.mediaFingerprint(
                        kind: .hls,
                        url: mediaCandidate.url
                    )
                    if self.isIndependentFromKnownEncryptedMedia(
                        fingerprint: mediaFingerprint,
                        knownFingerprints: knownEncryptedMediaFingerprints,
                        hasUnidentifiedKnownEncryptedMedia: hasUnidentifiedKnownEncryptedMedia
                    ) == false {
                        status = .failed(.unsupportedMediaKind)
                        routeFactsBySlot[.iframe] = VideoPreparedPlaybackRouteFact(
                            routeSlot: .iframe,
                            executionMode: .iframeResolve,
                            disposition: .rejectedBeforePlayer,
                            routeActivationURL: iframeActivationURL,
                            candidateMediaURL: mediaCandidate.url,
                            candidateMediaKind: .hls,
                            reason: .knownEncryptedMedia
                        )
                        break playbackLoop
                    }

                    let inspection: VideoHLSInitialManifestInspection = try await self.inspectInitialHLSManifest(
                        mediaURL: mediaCandidate.url,
                        source: source,
                        playbackRequestConfig: resolvedPlaybackRequest
                    )
                    switch inspection.classification {
                    case .encrypted:
                        status = .failed(.unsupportedMediaKind)
                        self.recordKnownEncryptedHLS(
                            candidateURL: mediaCandidate.url,
                            observedFinalURL: inspection.observedFinalURL,
                            knownFingerprints: &knownEncryptedMediaFingerprints,
                            hasUnidentifiedKnownEncryptedMedia: &hasUnidentifiedKnownEncryptedMedia
                        )
                        routeFactsBySlot[.iframe] = VideoPreparedPlaybackRouteFact(
                            routeSlot: .iframe,
                            executionMode: .iframeResolve,
                            disposition: .rejectedBeforePlayer,
                            routeActivationURL: iframeActivationURL,
                            candidateMediaURL: mediaCandidate.url,
                            candidateMediaKind: .hls,
                            reason: .encryptedHLS
                        )
                    case .unknown:
                        if knownEncryptedMediaFingerprints.isEmpty == false,
                           self.isIndependentFromKnownEncryptedMedia(
                               kind: .hls,
                               url: inspection.observedFinalURL,
                               knownFingerprints: knownEncryptedMediaFingerprints,
                               hasUnidentifiedKnownEncryptedMedia: hasUnidentifiedKnownEncryptedMedia
                           ) == false {
                            status = .failed(.unsupportedMediaKind)
                            routeFactsBySlot[.iframe] = VideoPreparedPlaybackRouteFact(
                                routeSlot: .iframe,
                                executionMode: .iframeResolve,
                                disposition: .rejectedBeforePlayer,
                                routeActivationURL: iframeActivationURL,
                                candidateMediaURL: mediaCandidate.url,
                                candidateMediaKind: .hls,
                                reason: .knownEncryptedMedia
                            )
                        } else {
                            candidateMediaURL = mediaCandidate.url
                            candidateMediaKind = .m3u8
                            playbackRequestConfig = resolvedPlaybackRequest
                            status = .playable
                            selectedRouteSlot = .iframe
                            routeFactsBySlot[.iframe] = VideoPreparedPlaybackRouteFact(
                                routeSlot: .iframe,
                                executionMode: .iframeResolve,
                                disposition: .selectedForPlayer,
                                routeActivationURL: iframeActivationURL,
                                candidateMediaURL: mediaCandidate.url,
                                candidateMediaKind: .hls,
                                reason: nil
                            )
                        }
                    }
                    break playbackLoop
                }

                if let iframeURL: URL = parsed.iframeURLs.first,
                   let iframeRule: VideoIframePlaybackRule = playbackRule.iframe {
                    let maxDepth: Int = iframeRule.maxDepth ?? 3
                    guard depth < maxDepth else {
                        status = .failed(.iframePlayerDepthExceeded)
                        routeFactsBySlot[.iframe] = VideoPreparedPlaybackRouteFact(
                            routeSlot: .iframe,
                            executionMode: .iframeResolve,
                            disposition: .rejectedBeforePlayer,
                            routeActivationURL: iframeActivationURL,
                            candidateMediaURL: nil,
                            candidateMediaKind: .unknown,
                            reason: .iframeDepthExceeded
                        )
                        break playbackLoop
                    }
                    guard visitedURLKeys.insert(self.canonicalURLKey(iframeURL)).inserted else {
                        status = .failed(.iframePlayerLoopDetected)
                        routeFactsBySlot[.iframe] = VideoPreparedPlaybackRouteFact(
                            routeSlot: .iframe,
                            executionMode: .iframeResolve,
                            disposition: .rejectedBeforePlayer,
                            routeActivationURL: iframeActivationURL,
                            candidateMediaURL: nil,
                            candidateMediaKind: .unknown,
                            reason: .iframeLoopDetected
                        )
                        break playbackLoop
                    }
                    depth += 1
                    refererURL = response.finalURL
                    currentURL = iframeURL
                    continue playbackLoop
                }

                status = .failed(.mediaURLNotFound)
                routeFactsBySlot[.iframe] = VideoPreparedPlaybackRouteFact(
                    routeSlot: .iframe,
                    executionMode: .iframeResolve,
                    disposition: .rejectedBeforePlayer,
                    routeActivationURL: iframeActivationURL,
                    candidateMediaURL: nil,
                    candidateMediaKind: .unknown,
                    reason: .noCandidate
                )
                break playbackLoop
            }

            if playbackRule.effectiveMediaCandidates.isEmpty == false {
                if let mediaCandidate, mediaCandidate.kind == .mp4 {
                    candidateMediaURL = mediaCandidate.url
                    candidateMediaKind = .mp4
                    playbackRequestConfig = try self.playbackRequest(
                        source: source,
                        rule: session.siteRule,
                        mediaRequest: playbackRule.mediaRequest,
                        finalURL: response.finalURL
                    )
                    status = .playable
                    selectedRouteSlot = .media
                    routeFactsBySlot[.media] = VideoPreparedPlaybackRouteFact(
                        routeSlot: .media,
                        executionMode: .directMedia,
                        disposition: .selectedForPlayer,
                        routeActivationURL: response.finalURL,
                        candidateMediaURL: mediaCandidate.url,
                        candidateMediaKind: .mp4,
                        reason: nil
                    )
                    break playbackLoop
                }

                if let mediaCandidate {
                    let resolvedPlaybackRequest: SourcePlaybackRequestConfig? = try self.playbackRequest(
                        source: source,
                        rule: session.siteRule,
                        mediaRequest: playbackRule.mediaRequest,
                        finalURL: response.finalURL
                    )
                    let inspection: VideoHLSInitialManifestInspection = try await self.inspectInitialHLSManifest(
                        mediaURL: mediaCandidate.url,
                        source: source,
                        playbackRequestConfig: resolvedPlaybackRequest
                    )
                    switch inspection.classification {
                    case .encrypted:
                        status = .failed(.unsupportedMediaKind)
                        self.recordKnownEncryptedHLS(
                            candidateURL: mediaCandidate.url,
                            observedFinalURL: inspection.observedFinalURL,
                            knownFingerprints: &knownEncryptedMediaFingerprints,
                            hasUnidentifiedKnownEncryptedMedia: &hasUnidentifiedKnownEncryptedMedia
                        )
                        routeFactsBySlot[.media] = VideoPreparedPlaybackRouteFact(
                            routeSlot: .media,
                            executionMode: .directMedia,
                            disposition: .rejectedBeforePlayer,
                            routeActivationURL: response.finalURL,
                            candidateMediaURL: mediaCandidate.url,
                            candidateMediaKind: .hls,
                            reason: .encryptedHLS
                        )
                    case .unknown:
                        candidateMediaURL = mediaCandidate.url
                        candidateMediaKind = .m3u8
                        playbackRequestConfig = resolvedPlaybackRequest
                        status = .playable
                        selectedRouteSlot = .media
                        routeFactsBySlot[.media] = VideoPreparedPlaybackRouteFact(
                            routeSlot: .media,
                            executionMode: .directMedia,
                            disposition: .selectedForPlayer,
                            routeActivationURL: response.finalURL,
                            candidateMediaURL: mediaCandidate.url,
                            candidateMediaKind: .hls,
                            reason: nil
                        )
                        break playbackLoop
                    }
                } else {
                    routeFactsBySlot[.media] = VideoPreparedPlaybackRouteFact(
                        routeSlot: .media,
                        executionMode: .directMedia,
                        disposition: .rejectedBeforePlayer,
                        routeActivationURL: response.finalURL,
                        candidateMediaURL: nil,
                        candidateMediaKind: self.declaredRuntimeMediaKind(playbackRule),
                        reason: .noCandidate
                    )
                }
            }

            if let iframeRule: VideoIframePlaybackRule = playbackRule.iframe {
                guard let iframeURL: URL = parsed.iframeURLs.first else {
                    routeFactsBySlot[.iframe] = VideoPreparedPlaybackRouteFact(
                        routeSlot: .iframe,
                        executionMode: iframeRule.strategy == .resolve ? .iframeResolve : .webUI,
                        disposition: .rejectedBeforePlayer,
                        routeActivationURL: response.finalURL,
                        candidateMediaURL: nil,
                        candidateMediaKind: .unknown,
                        reason: .noCandidate
                    )
                    break playbackLoop
                }

                iframeActivationURL = iframeURL
                switch iframeRule.strategy {
                case .webUI:
                    if knownEncryptedMediaFingerprints.isEmpty == false
                        || hasUnidentifiedKnownEncryptedMedia {
                        status = .failed(.unsupportedMediaKind)
                        routeFactsBySlot[.iframe] = VideoPreparedPlaybackRouteFact(
                            routeSlot: .iframe,
                            executionMode: .webUI,
                            disposition: .rejectedBeforePlayer,
                            routeActivationURL: iframeURL,
                            candidateMediaURL: nil,
                            candidateMediaKind: .unknown,
                            reason: .finalMediaObservationUnavailable
                        )
                    } else {
                        candidateMediaURL = iframeURL
                        candidateMediaKind = .iframePlayer
                        playbackRequestConfig = self.webPlaybackRequest(
                            request: request,
                            referer: response.finalURL
                        )
                        status = .pageOnly
                        selectedRouteSlot = .iframe
                        routeFactsBySlot[.iframe] = VideoPreparedPlaybackRouteFact(
                            routeSlot: .iframe,
                            executionMode: .webUI,
                            disposition: .selectedForPlayer,
                            routeActivationURL: iframeURL,
                            candidateMediaURL: nil,
                            candidateMediaKind: .unknown,
                            reason: nil
                        )
                    }
                    break playbackLoop
                case .resolve:
                    let maxDepth: Int = iframeRule.maxDepth ?? 3
                    guard depth < maxDepth else {
                        status = .failed(.iframePlayerDepthExceeded)
                        routeFactsBySlot[.iframe] = VideoPreparedPlaybackRouteFact(
                            routeSlot: .iframe,
                            executionMode: .iframeResolve,
                            disposition: .rejectedBeforePlayer,
                            routeActivationURL: iframeURL,
                            candidateMediaURL: nil,
                            candidateMediaKind: .unknown,
                            reason: .iframeDepthExceeded
                        )
                        break playbackLoop
                    }
                    guard visitedURLKeys.insert(self.canonicalURLKey(iframeURL)).inserted else {
                        status = .failed(.iframePlayerLoopDetected)
                        routeFactsBySlot[.iframe] = VideoPreparedPlaybackRouteFact(
                            routeSlot: .iframe,
                            executionMode: .iframeResolve,
                            disposition: .rejectedBeforePlayer,
                            routeActivationURL: iframeURL,
                            candidateMediaURL: nil,
                            candidateMediaKind: .unknown,
                            reason: .iframeLoopDetected
                        )
                        break playbackLoop
                    }
                    resolvingIframeRoute = true
                    depth += 1
                    refererURL = response.finalURL
                    currentURL = iframeURL
                    continue playbackLoop
                }
            }

            break playbackLoop
        }

        if selectedRouteSlot == nil, playbackRule.fallback == .webUI {
            let fallbackURL: URL = lastResponseFinalURL ?? rootFinalURL ?? requestURL
            if knownEncryptedMediaFingerprints.isEmpty == false
                || hasUnidentifiedKnownEncryptedMedia {
                status = .failed(.unsupportedMediaKind)
                routeFactsBySlot[.fallback] = VideoPreparedPlaybackRouteFact(
                    routeSlot: .fallback,
                    executionMode: .webUI,
                    disposition: .rejectedBeforePlayer,
                    routeActivationURL: fallbackURL,
                    candidateMediaURL: nil,
                    candidateMediaKind: .unknown,
                    reason: .finalMediaObservationUnavailable
                )
            } else {
                candidateMediaURL = fallbackURL
                candidateMediaKind = .iframePlayer
                playbackRequestConfig = self.webPlaybackRequest(
                    request: request,
                    referer: fallbackURL
                )
                status = .pageOnly
                selectedRouteSlot = .fallback
                routeFactsBySlot[.fallback] = VideoPreparedPlaybackRouteFact(
                    routeSlot: .fallback,
                    executionMode: .webUI,
                    disposition: .selectedForPlayer,
                    routeActivationURL: fallbackURL,
                    candidateMediaURL: nil,
                    candidateMediaKind: .unknown,
                    reason: nil
                )
            }
        }

        if selectedRouteSlot != nil {
            for route in session.declaredRoutes where routeFactsBySlot[route.routeSlot] == nil {
                routeFactsBySlot[route.routeSlot] = VideoPreparedPlaybackRouteFact(
                    routeSlot: route.routeSlot,
                    executionMode: route.executionMode,
                    disposition: .skipped,
                    routeActivationURL: nil,
                    candidateMediaURL: nil,
                    candidateMediaKind: .unknown,
                    reason: .priorRouteSelected
                )
            }
        }

        let routeFacts: [VideoPreparedPlaybackRouteFact] = try session.declaredRoutes.map { route in
            guard let fact: VideoPreparedPlaybackRouteFact = routeFactsBySlot[route.routeSlot] else {
                throw SourceRuntimeError.invalidInput(
                    "Prepared playback route state is incomplete for \(route.routeSlot.rawValue)."
                )
            }
            return fact
        }

        let finalPlayPageURL: URL = rootFinalURL ?? requestURL
        let reference = SourceVideoPlaybackReference(
            vodID: handoff.vodID,
            sourceIndex: handoff.sourceIndex,
            episodeIndex: handoff.episodeIndex,
            episodeKey: handoff.episodeKey,
            episodeTitle: handoff.episodeTitle,
            playPageURL: finalPlayPageURL,
            candidateMediaURL: candidateMediaURL,
            candidateMediaKind: candidateMediaKind,
            playbackRequestConfig: playbackRequestConfig,
            nextEpisodeURL: handoff.nextEpisodeURL,
            previousEpisodeURL: handoff.previousEpisodeURL,
            sourceName: handoff.sourceName ?? source.name,
            status: status,
            handoff: handoff
        )
        let output = SourceVideoPlaybackOutput(
            reference: reference,
            diagnostics: SourceRuntimeDiagnostics.succeeded(
                requestLogs: requestLogs,
                extractionLogs: extractionLogs,
                issues: issues,
                context: SourceRuntimeDiagnosticContext(
                    runtimeContext: input.context,
                    requestURL: self.safeLogURL(finalPlayPageURL)
                )
            )
        )
        return VideoPreparedPlaybackExecutionResult(
            output: output,
            routeFacts: routeFacts
        )
    }

    private func validateParsedPlayback(
        _ parsed: VideoRuleParsedPlayback,
        rule: VideoPlaybackRule,
        sourceID: String
    ) throws {
        if parsed.invalidMediaURLCount > 0 {
            throw RuleExecutionError.ruleConfiguration(
                stage: .playback,
                sourceID: sourceID,
                reason: "Video V2 playback rule \(rule.id) produced \(parsed.invalidMediaURLCount) unsupported or invalid media URL value(s)."
            )
        }
        if parsed.invalidIframeURLCount > 0 {
            throw RuleExecutionError.ruleConfiguration(
                stage: .playback,
                sourceID: sourceID,
                reason: "Video V2 playback rule \(rule.id) produced \(parsed.invalidIframeURLCount) unsupported or invalid iframe URL value(s)."
            )
        }
        if parsed.iframeURLs.count > 1 {
            throw RuleExecutionError.responseContract(
                stage: .playback,
                sourceID: sourceID,
                reason: "Video V2 playback rule \(rule.id) produced multiple distinct iframe URLs."
            )
        }
    }

    // 中文注释：只检查规则已解析出的初始 HLS manifest；失败或未命中 key tag 均保持 unknown。
    private func inspectInitialHLSManifest(
        mediaURL: URL,
        source: Source,
        playbackRequestConfig: SourcePlaybackRequestConfig?
    ) async throws -> VideoHLSInitialManifestInspection {
        do {
            let response: PageContentResponse = try await self.pageContentLoader.loadContent(
                PageLoadRequest(
                    url: mediaURL,
                    requestConfig: self.initialHLSManifestRequest(playbackRequestConfig),
                    sourceContext: SourceRequestContext(
                        sourceID: source.id,
                        baseURL: URL(string: source.baseURL),
                        purpose: .video,
                        refererURL: playbackRequestConfig?.referer
                    ),
                    cachePolicy: .reloadIgnoringLocalCacheData
                )
            )
            return VideoHLSInitialManifestInspection(
                classification: VideoHLSManifestEncryptionClassifier.classify(response.content),
                observedFinalURL: response.finalURL
            )
        } catch {
            try Task.checkCancellation()
            return VideoHLSInitialManifestInspection(
                classification: .unknown,
                observedFinalURL: nil
            )
        }
    }

    private func initialHLSManifestRequest(
        _ playbackRequestConfig: SourcePlaybackRequestConfig?
    ) -> RequestConfig {
        var headers: [String: String] = playbackRequestConfig?.headers ?? [:]
        if let referer: URL = playbackRequestConfig?.referer,
           RequestHeaderFields.containsHeader("Referer", in: headers) == false {
            headers["Referer"] = referer.absoluteString
        }
        if let referer: URL = playbackRequestConfig?.referer,
           RequestHeaderFields.containsHeader("Origin", in: headers) == false,
           let origin: String = RequestHeaderFields.originHeader(from: referer) {
            headers["Origin"] = origin
        }
        if let userAgent: String = playbackRequestConfig?.userAgent,
           RequestHeaderFields.containsHeader("User-Agent", in: headers) == false {
            headers["User-Agent"] = userAgent
        }
        return RequestConfig(
            scope: .rule,
            mergePolicy: .mergeHeadersAndCookies,
            method: .get,
            headers: headers.isEmpty ? nil : headers,
            cookiePolicy: playbackRequestConfig?.cookiePolicy,
            cookiePriority: playbackRequestConfig?.cookiePriority,
            needsWebView: false,
            autoScroll: false
        )
    }

    private func mediaFingerprint(
        kind: VideoRuntimeEvidenceMediaKind,
        url: URL
    ) -> VideoRuntimeEvidenceFingerprint? {
        return try? VideoRuntimeEvidenceFingerprintFactory.media(
            kind: kind,
            resourceURL: url
        )
    }

    private func isIndependentFromKnownEncryptedMedia(
        kind: VideoRuntimeEvidenceMediaKind,
        url: URL?,
        knownFingerprints: Set<VideoRuntimeEvidenceFingerprint>,
        hasUnidentifiedKnownEncryptedMedia: Bool
    ) -> Bool {
        guard let url else {
            return false
        }
        return self.isIndependentFromKnownEncryptedMedia(
            fingerprint: self.mediaFingerprint(kind: kind, url: url),
            knownFingerprints: knownFingerprints,
            hasUnidentifiedKnownEncryptedMedia: hasUnidentifiedKnownEncryptedMedia
        )
    }

    private func isIndependentFromKnownEncryptedMedia(
        fingerprint: VideoRuntimeEvidenceFingerprint?,
        knownFingerprints: Set<VideoRuntimeEvidenceFingerprint>,
        hasUnidentifiedKnownEncryptedMedia: Bool
    ) -> Bool {
        guard hasUnidentifiedKnownEncryptedMedia == false else {
            return false
        }
        guard knownFingerprints.isEmpty == false else {
            return true
        }
        guard let fingerprint else {
            return false
        }
        return knownFingerprints.contains(fingerprint) == false
    }

    private func recordKnownEncryptedHLS(
        candidateURL: URL,
        observedFinalURL: URL?,
        knownFingerprints: inout Set<VideoRuntimeEvidenceFingerprint>,
        hasUnidentifiedKnownEncryptedMedia: inout Bool
    ) {
        guard let candidateFingerprint: VideoRuntimeEvidenceFingerprint = self.mediaFingerprint(
            kind: .hls,
            url: candidateURL
        ) else {
            hasUnidentifiedKnownEncryptedMedia = true
            return
        }
        knownFingerprints.insert(candidateFingerprint)
        if let observedFinalURL,
           let finalFingerprint: VideoRuntimeEvidenceFingerprint = self.mediaFingerprint(
               kind: .hls,
               url: observedFinalURL
           ) {
            knownFingerprints.insert(finalFingerprint)
        }
    }

    private func webPlaybackRequest(
        request: RequestConfig?,
        referer: URL
    ) -> SourcePlaybackRequestConfig {
        var headers: [String: String] = request?.headers ?? [:]
        headers = RequestHeaderFields.applyingOverrides(
            ["Referer": referer.absoluteString],
            to: headers
        )
        return SourcePlaybackRequestConfig(
            headers: headers,
            referer: referer,
            userAgent: nil,
            cookiePolicy: request?.cookiePolicy,
            cookiePriority: request?.cookiePriority
        )
    }

    private func playbackSelector(_ rule: VideoPlaybackRule) -> String {
        if rule.effectiveMediaCandidates.isEmpty == false {
            let selectors: [String] = rule.effectiveMediaCandidates.compactMap { mediaRule in
                guard let selector: String = mediaRule.url.selector?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      selector.isEmpty == false else {
                    return nil
                }
                return selector
            }
            return selectors.isEmpty ? "document" : selectors.joined(separator: " | ")
        }
        return rule.iframe?.url.selector ?? "document"
    }

    private func handoff(_ input: SourceVideoPlaybackInput) throws -> SourceVideoPlaybackHandoff {
        guard let handoff: SourceVideoPlaybackHandoff = input.handoff?.selecting(
            playPageURL: input.playPageURL
        ) ?? input.handoff else {
            throw SourceRuntimeError.invalidInput(
                "Video V2 playback requires the stable detail or episode handoff."
            )
        }
        return handoff
    }

    private func entry(
        input: SourceVideoPlaybackInput,
        handoff: SourceVideoPlaybackHandoff,
        resolvedRule: ResolvedVideoSiteRule
    ) throws -> ResolvedVideoPlaybackEntry {
        let pageID: String? = input.context.pageID ?? input.context.tabID ?? handoff.pageID
        let listRuleID: String? = input.context.ruleID ?? handoff.listRuleID
        var entries: [ResolvedVideoPlaybackEntry] = resolvedRule.playbackEntries
        if let pageID: String {
            entries = entries.filter { $0.pageID == pageID }
        }
        if let listRuleID: String {
            entries = entries.filter { $0.listRuleID == listRuleID }
        }
        guard entries.count == 1, let entry: ResolvedVideoPlaybackEntry = entries.first else {
            throw SourceRuntimeError.invalidInput(
                entries.isEmpty
                    ? "Video V2 playback rule chain was not found for the detail or episode handoff."
                    : "Video V2 playback rule chain is ambiguous for the detail or episode handoff."
            )
        }
        return entry
    }

    private func playbackRequest(
        source: Source,
        rule: VideoSiteRule,
        mediaRequest: VideoMediaRequestRule?,
        finalURL: URL
    ) throws -> SourcePlaybackRequestConfig? {
        let sourceBaseURL: URL
        if let value: URL = URL(string: rule.baseUrl) {
            sourceBaseURL = value
        } else {
            throw RuleExecutionError.ruleConfiguration(
                stage: .playback,
                sourceID: source.id,
                reason: "Video V2 source base URL is invalid."
            )
        }
        let templateContext = BrowseCraftCore.VideoPlaybackTemplateContext(
            sourceID: source.id,
            sourceBaseURL: sourceBaseURL,
            contextValues: VideoRuleAPITemplateResolver.resolvedContextValues(
                source: source,
                rule: rule,
                credentialProvider: self.credentialProvider
            ),
            finalURL: finalURL
        )
        do {
            var headers: [String: String] = [:]
            for (key, value) in mediaRequest?.headers ?? [:] {
                headers[key] = try self.templateResolver.resolve(value, context: templateContext)
            }
            let referer: URL
            if let template: String = mediaRequest?.referer {
                let value: String = try self.templateResolver.resolve(template, context: templateContext)
                guard let resolvedURL: URL = self.absoluteHTTPURL(value) else {
                    throw VideoPlaybackRequestError.invalidReferer
                }
                referer = resolvedURL
            } else {
                referer = finalURL
            }
            headers = RequestHeaderFields.applyingOverrides(
                ["Referer": referer.absoluteString],
                to: headers
            )
            let userAgent: String?
            if RequestHeaderFields.containsHeader("User-Agent", in: headers) {
                userAgent = nil
            } else if let template: String = mediaRequest?.userAgent {
                userAgent = try self.templateResolver.resolve(template, context: templateContext)
            } else {
                userAgent = nil
            }
            return SourcePlaybackRequestConfig(
                headers: headers,
                referer: referer,
                userAgent: userAgent,
                cookiePolicy: mediaRequest?.cookiePolicy,
                cookiePriority: mediaRequest?.cookiePriority
            )
        } catch {
            throw RuleExecutionError.ruleConfiguration(
                stage: .playback,
                sourceID: source.id,
                reason: "Video V2 mediaRequest cannot be resolved: \(error.localizedDescription)"
            )
        }
    }

    private func requestURL(_ input: SourceVideoPlaybackInput) throws -> URL {
        let url: URL = input.context.requestOverride?.url ?? input.playPageURL
        guard let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            throw SourceRuntimeError.invalidInput(
                "Video V2 playback page URL must use HTTP(S)."
            )
        }
        return url
    }

    private func declaredRuntimeMediaKind(
        _ rule: VideoPlaybackRule
    ) -> VideoRuntimeEvidenceMediaKind {
        let kinds: Set<VideoDirectMediaKind> = Set(
            rule.effectiveMediaCandidates.map(\.kind)
        )
        guard kinds.count == 1, let kind: VideoDirectMediaKind = kinds.first else {
            return .unknown
        }
        switch kind {
        case .mp4:
            return .mp4
        case .hls:
            return .hls
        }
    }

    private func absoluteHTTPURL(_ value: String) -> URL? {
        guard let url: URL = URL(string: value),
              let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    private func safeLogURL(_ url: URL) -> URL {
        guard var components: URLComponents = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url
        }
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    private func canonicalURLKey(_ url: URL) -> String {
        var components: URLComponents? = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url?.absoluteString ?? url.absoluteString
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

enum VideoHLSInitialManifestClassification: Hashable, Sendable {
    case unknown
    case encrypted
}

struct VideoHLSInitialManifestInspection: Hashable, Sendable {
    let classification: VideoHLSInitialManifestClassification
    let observedFinalURL: URL?
}

// 中文注释：这里只做有界、纯文本 tag 分类；永不请求 key/IV，也永不把未命中升级为 unencrypted。
enum VideoHLSManifestEncryptionClassifier {
    static let maximumAnalyzedByteCount: Int = 256 * 1_024

    static func classify(_ manifest: String) -> VideoHLSInitialManifestClassification {
        let boundedManifest: String = String(
            decoding: manifest.utf8.prefix(self.maximumAnalyzedByteCount),
            as: UTF8.self
        )
        let lines: [Substring] = boundedManifest.split(
            omittingEmptySubsequences: true,
            whereSeparator: \.isNewline
        )
        let firstLineCharacterSet: CharacterSet = .whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "\u{feff}")
        )
        guard let firstLine: Substring = lines.first,
              String(firstLine).trimmingCharacters(in: firstLineCharacterSet) == "#EXTM3U" else {
            return .unknown
        }

        for rawLine: Substring in lines.dropFirst() {
            let line: String = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if self.hasNonemptyAttributes(line, tag: "#EXT-X-SESSION-KEY:") {
                return .encrypted
            }
            if let method: String = self.attribute("METHOD", in: line, tag: "#EXT-X-KEY:"),
               method.caseInsensitiveCompare("NONE") != .orderedSame {
                return .encrypted
            }
        }
        return .unknown
    }

    private static func hasNonemptyAttributes(_ line: String, tag: String) -> Bool {
        guard line.hasPrefix(tag) else {
            return false
        }
        return line.dropFirst(tag.count).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private static func attribute(_ name: String, in line: String, tag: String) -> String? {
        guard line.hasPrefix(tag) else {
            return nil
        }
        let attributes: Substring = line.dropFirst(tag.count)
        for rawAttribute: Substring in attributes.split(separator: ",") {
            let pair: [Substring] = rawAttribute.split(separator: "=", maxSplits: 1)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(name) == .orderedSame else {
                continue
            }
            let value: String = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}

private enum VideoPlaybackRequestError: LocalizedError {
    case invalidReferer

    var errorDescription: String? {
        return "mediaRequest.referer must resolve to an absolute HTTP(S) URL."
    }
}
