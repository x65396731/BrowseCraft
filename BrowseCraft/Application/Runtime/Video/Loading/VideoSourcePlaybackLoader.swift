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

        var currentURL: URL = requestURL
        var refererURL: URL = requestURL
        var rootFinalURL: URL?
        var depth: Int = 0
        var visitedURLKeys: Set<String> = [self.canonicalURLKey(requestURL)]
        var requestLogs: [SourceRequestLog] = []
        var extractionLogs: [SourceExtractionLog] = []
        var issues: [SourceRuntimeIssue] = []
        var candidateMediaURL: URL?
        var candidateMediaKind: SourceVideoMediaKind = .unknown
        var playbackRequestConfig: SourcePlaybackRequestConfig?
        var status: SourceVideoPlaybackStatus = .failed(.mediaURLNotFound)

        playbackLoop: while true {
            let response: PageContentResponse = try await self.pageContentLoader.getStringResponse(
                from: currentURL,
                request: request,
                context: SourceRequestContext(
                    sourceID: source.id,
                    baseURL: URL(string: source.baseURL),
                    purpose: .video,
                    refererURL: refererURL
                )
            )
            rootFinalURL = rootFinalURL ?? response.finalURL
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
            if let mediaRule: VideoDirectMediaRule = playbackRule.media {
                extractionLogs.append(
                    SourceExtractionLog(
                        field: "playback.dom.media.depth\(depth)",
                        selector: mediaRule.url.selector,
                        candidateCount: parsed.mediaCandidateCount,
                        outputCount: parsed.mediaURLs.count
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
            if let mediaURL: URL = parsed.mediaURLs.first,
               let mediaRule: VideoDirectMediaRule = playbackRule.media {
                candidateMediaURL = mediaURL
                candidateMediaKind = self.mediaKind(mediaRule.kind)
                playbackRequestConfig = try self.playbackRequest(
                    source: source,
                    rule: resolvedRule.raw,
                    mediaRequest: playbackRule.mediaRequest,
                    finalURL: response.finalURL
                )
                status = .playable
                break playbackLoop
            }

            if let iframeURL: URL = parsed.iframeURLs.first,
               let iframeRule: VideoIframePlaybackRule = playbackRule.iframe {
                switch iframeRule.strategy {
                case .webUI:
                    candidateMediaURL = iframeURL
                    candidateMediaKind = .iframePlayer
                    playbackRequestConfig = self.webPlaybackRequest(
                        request: request,
                        referer: response.finalURL
                    )
                    status = .pageOnly
                    break playbackLoop
                case .resolve:
                    let maxDepth: Int = iframeRule.maxDepth ?? 3
                    guard depth < maxDepth else {
                        candidateMediaURL = iframeURL
                        candidateMediaKind = .iframePlayer
                        status = .failed(.iframePlayerDepthExceeded)
                        break playbackLoop
                    }
                    guard visitedURLKeys.insert(self.canonicalURLKey(iframeURL)).inserted else {
                        candidateMediaURL = iframeURL
                        candidateMediaKind = .iframePlayer
                        status = .failed(.iframePlayerLoopDetected)
                        break playbackLoop
                    }
                    depth += 1
                    refererURL = response.finalURL
                    currentURL = iframeURL
                    continue playbackLoop
                }
            }

            if playbackRule.fallback == .webUI {
                candidateMediaURL = response.finalURL
                candidateMediaKind = .iframePlayer
                playbackRequestConfig = self.webPlaybackRequest(
                    request: request,
                    referer: response.finalURL
                )
                status = .pageOnly
            }
            break playbackLoop
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
        return SourceVideoPlaybackOutput(
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
        if parsed.mediaURLs.count > 1 {
            throw RuleExecutionError.responseContract(
                stage: .playback,
                sourceID: sourceID,
                reason: "Video V2 playback rule \(rule.id) produced multiple distinct direct media URLs."
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

    private func webPlaybackRequest(
        request: RequestConfig?,
        referer: URL
    ) -> SourcePlaybackRequestConfig {
        var headers: [String: String] = request?.headers ?? [:]
        headers = BrowserRequestHeaders.applyingOverrides(
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
        return rule.media?.url.selector ?? rule.iframe?.url.selector ?? "document"
    }

    private func handoff(_ input: SourceVideoPlaybackInput) throws -> SourceVideoPlaybackHandoff {
        guard let handoff: SourceVideoPlaybackHandoff = input.handoff?.selecting(
            playPageURL: input.playPageURL
        ) ?? input.handoff else {
            throw SourceRuntimeError.invalidInput(
                "Video V2 playback requires the stable detail/episode handoff."
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
                    ? "Video V2 playback rule chain was not found for the episode handoff."
                    : "Video V2 playback rule chain is ambiguous for the episode handoff."
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
            headers = BrowserRequestHeaders.applyingOverrides(
                ["Referer": referer.absoluteString],
                to: headers
            )
            let userAgent: String?
            if BrowserRequestHeaders.containsHeader("User-Agent", in: headers) {
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

    private func mediaKind(_ kind: VideoDirectMediaKind) -> SourceVideoMediaKind {
        switch kind {
        case .mp4:
            return .mp4
        case .hls:
            return .m3u8
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

private enum VideoPlaybackRequestError: LocalizedError {
    case invalidReferer

    var errorDescription: String? {
        return "mediaRequest.referer must resolve to an absolute HTTP(S) URL."
    }
}
