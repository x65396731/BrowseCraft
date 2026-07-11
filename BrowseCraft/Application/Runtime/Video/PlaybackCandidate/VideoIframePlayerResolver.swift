import Foundation
import BrowseCraftCore

// 中文注释：VideoIframePlayerResolver 只处理播放层 iframe 二跳，不处理内容层 frame shell、WebView 或插件执行。
struct VideoIframePlayerResolution {
    var reference: SourceVideoPlaybackReference
    var requestLogs: [SourceRequestLog]
    var issues: [SourceRuntimeIssue]
}

struct VideoIframePlayerResolver {
    private let pageContentLoader: PageContentLoader
    private let mapper: any VideoContentMapper
    private let requestConfigResolver: VideoRequestConfigResolver
    private let maxDepth: Int

    init(
        pageContentLoader: PageContentLoader,
        mapper: any VideoContentMapper,
        requestConfigResolver: VideoRequestConfigResolver = VideoRequestConfigResolver(),
        maxDepth: Int = 2
    ) {
        self.pageContentLoader = pageContentLoader
        self.mapper = mapper
        self.requestConfigResolver = requestConfigResolver
        self.maxDepth = maxDepth
    }

    func resolve(
        reference: SourceVideoPlaybackReference,
        definition: SourceDefinition,
        baseRequest: RequestConfig?
    ) async throws -> VideoIframePlayerResolution? {
        guard reference.candidateMediaKind == .iframePlayer,
              let iframePlayerURL: URL = reference.candidateMediaURL else {
            return nil
        }
        guard iframePlayerURL != reference.playPageURL else {
            return nil
        }
        if self.isTerminalIframePlayerURL(iframePlayerURL) {
            return nil
        }

        return try await self.resolve(
            originalReference: reference,
            currentURL: iframePlayerURL,
            refererURL: reference.playPageURL,
            definition: definition,
            baseRequest: baseRequest,
            depth: 1,
            visitedURLs: Set<String>([reference.playPageURL.absoluteString])
        )
    }

    private func isTerminalIframePlayerURL(_ url: URL) -> Bool {
        guard let host: String = url.host?.lowercased() else {
            return false
        }

        let path: String = url.path.lowercased()
        if (host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com")),
           path.hasPrefix("/embed/") {
            return true
        }

        return false
    }

    private func resolve(
        originalReference: SourceVideoPlaybackReference,
        currentURL: URL,
        refererURL: URL,
        definition: SourceDefinition,
        baseRequest: RequestConfig?,
        depth: Int,
        visitedURLs: Set<String>
    ) async throws -> VideoIframePlayerResolution {
        if depth > self.maxDepth {
            return VideoIframePlayerResolution(
                reference: self.reference(
                    from: originalReference,
                    status: .failed(.iframePlayerDepthExceeded)
                ),
                requestLogs: [],
                issues: [
                    SourceRuntimeIssue(
                        id: "video.iframePlayerDepthExceeded",
                        severity: .warning,
                        message: "Video playback iframe player exceeded max depth \(self.maxDepth)."
                    )
                ]
            )
        }

        let currentKey: String = currentURL.absoluteString
        if visitedURLs.contains(currentKey) {
            return VideoIframePlayerResolution(
                reference: self.reference(
                    from: originalReference,
                    status: .failed(.iframePlayerLoopDetected)
                ),
                requestLogs: [],
                issues: [
                    SourceRuntimeIssue(
                        id: "video.iframePlayerLoopDetected",
                        severity: .warning,
                        message: "Video playback iframe player loop detected at \(currentURL.absoluteString)."
                    )
                ]
            )
        }

        let request: RequestConfig? = self.request(
            base: baseRequest,
            refererURL: refererURL
        )
        let html: String
        do {
            html = try await self.pageContentLoader.getString(from: currentURL, request: request)
        } catch {
            throw self.requestConfigResolver.mappedLoadingError(error, url: currentURL)
        }

        let iframePlayerLog: SourceRequestLog = self.requestConfigResolver.requestLog(
            url: currentURL,
            request: request,
            html: html
        )
        let iframePlayerReference: SourceVideoPlaybackReference = try self.mapper.mapPlayback(
            html: html,
            definition: definition,
            playPageURL: currentURL
        )
        let loadedIssue: SourceRuntimeIssue = self.iframePlayerLoadedIssue(depth: depth)

        switch iframePlayerReference.status {
        case .playable:
            return VideoIframePlayerResolution(
                reference: self.reference(
                    from: originalReference,
                    iframePlayerReference: iframePlayerReference
                ),
                requestLogs: [iframePlayerLog],
                issues: [
                    loadedIssue,
                    SourceRuntimeIssue(
                        id: "video.iframePlayerMediaFound",
                        severity: .info,
                        message: "Video iframe player media found at depth \(depth)."
                    )
                ]
            )
        case .restricted(.captchaOrAntiBot):
            return VideoIframePlayerResolution(
                reference: self.reference(
                    from: originalReference,
                    status: .restricted(.captchaOrAntiBot)
                ),
                requestLogs: [iframePlayerLog],
                issues: [
                    loadedIssue,
                    SourceRuntimeIssue(
                        id: "video.blockedByAntiBot",
                        severity: .error,
                        message: "Video iframe player appears blocked by anti-bot or captcha protection."
                    )
                ]
            )
        case .pageOnly where iframePlayerReference.candidateMediaKind == .iframePlayer && iframePlayerReference.candidateMediaURL != nil,
             .failed(.mediaURLNotFound) where iframePlayerReference.candidateMediaKind == .iframePlayer && iframePlayerReference.candidateMediaURL != nil:
            guard let nextIframePlayerURL: URL = iframePlayerReference.candidateMediaURL else {
                return VideoIframePlayerResolution(
                    reference: self.reference(
                        from: originalReference,
                        status: .failed(.mediaURLNotFound)
                    ),
                    requestLogs: [iframePlayerLog],
                    issues: [
                        loadedIssue,
                        self.iframePlayerMediaMissingIssue()
                    ]
                )
            }

            var nextVisitedURLs: Set<String> = visitedURLs
            nextVisitedURLs.insert(currentKey)
            let nextResolution: VideoIframePlayerResolution = try await self.resolve(
                originalReference: originalReference,
                currentURL: nextIframePlayerURL,
                refererURL: currentURL,
                definition: definition,
                baseRequest: baseRequest,
                depth: depth + 1,
                visitedURLs: nextVisitedURLs
            )
            return VideoIframePlayerResolution(
                reference: nextResolution.reference,
                requestLogs: [iframePlayerLog] + nextResolution.requestLogs,
                issues: [loadedIssue] + nextResolution.issues
            )
        case .failed(.mediaURLNotFound), .pageOnly:
            return VideoIframePlayerResolution(
                reference: self.reference(
                    from: originalReference,
                    status: .failed(.mediaURLNotFound)
                ),
                requestLogs: [iframePlayerLog],
                issues: [
                    loadedIssue,
                    self.iframePlayerMediaMissingIssue()
                ]
            )
        case .restricted(_), .failed(_):
            return VideoIframePlayerResolution(
                reference: self.reference(
                    from: originalReference,
                    iframePlayerReference: iframePlayerReference
                ),
                requestLogs: [iframePlayerLog],
                issues: [loadedIssue] + self.requestConfigResolver.playbackIssues(reference: iframePlayerReference)
            )
        }
    }

    private func request(base: RequestConfig?, refererURL: URL) -> RequestConfig {
        var headers: [String: String] = base?.headers ?? [:]
        headers["Referer"] = refererURL.absoluteString

        return RequestConfig(
            scope: base?.scope,
            mergePolicy: base?.mergePolicy,
            method: base?.method,
            headers: headers,
            body: base?.body,
            cookiePolicy: base?.cookiePolicy,
            cookiePriority: base?.cookiePriority,
            cookieScope: base?.cookieScope,
            charset: base?.charset,
            needsWebView: false,
            autoScroll: base?.autoScroll,
            imageHeaders: base?.imageHeaders,
            imageRequest: base?.imageRequest
        )
    }

    private func reference(
        from originalReference: SourceVideoPlaybackReference,
        iframePlayerReference: SourceVideoPlaybackReference
    ) -> SourceVideoPlaybackReference {
        return SourceVideoPlaybackReference(
            vodID: originalReference.vodID,
            sourceIndex: originalReference.sourceIndex,
            episodeIndex: originalReference.episodeIndex,
            episodeKey: originalReference.episodeKey,
            episodeTitle: originalReference.episodeTitle ?? iframePlayerReference.episodeTitle,
            playPageURL: originalReference.playPageURL,
            candidateMediaURL: iframePlayerReference.candidateMediaURL,
            candidateMediaKind: iframePlayerReference.candidateMediaKind,
            playbackRequestConfig: iframePlayerReference.playbackRequestConfig,
            nextEpisodeURL: originalReference.nextEpisodeURL,
            previousEpisodeURL: originalReference.previousEpisodeURL,
            sourceName: originalReference.sourceName ?? iframePlayerReference.sourceName,
            status: iframePlayerReference.status
        )
    }

    private func reference(
        from originalReference: SourceVideoPlaybackReference,
        status: SourceVideoPlaybackStatus
    ) -> SourceVideoPlaybackReference {
        return SourceVideoPlaybackReference(
            vodID: originalReference.vodID,
            sourceIndex: originalReference.sourceIndex,
            episodeIndex: originalReference.episodeIndex,
            episodeKey: originalReference.episodeKey,
            episodeTitle: originalReference.episodeTitle,
            playPageURL: originalReference.playPageURL,
            candidateMediaURL: originalReference.candidateMediaURL,
            candidateMediaKind: originalReference.candidateMediaKind,
            playbackRequestConfig: originalReference.playbackRequestConfig,
            nextEpisodeURL: originalReference.nextEpisodeURL,
            previousEpisodeURL: originalReference.previousEpisodeURL,
            sourceName: originalReference.sourceName,
            status: status
        )
    }

    private func iframePlayerLoadedIssue(depth: Int) -> SourceRuntimeIssue {
        return SourceRuntimeIssue(
            id: "video.iframePlayerLoaded",
            severity: .info,
            message: "Video iframe player loaded at depth \(depth)."
        )
    }

    private func iframePlayerMediaMissingIssue() -> SourceRuntimeIssue {
        return SourceRuntimeIssue(
            id: "video.iframePlayerMediaMissing",
            severity: .warning,
            message: "Video iframe player loaded but did not expose a playable media URL."
        )
    }
}
