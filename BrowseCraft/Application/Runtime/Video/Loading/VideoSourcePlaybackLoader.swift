import Foundation
import BrowseCraftCore

// 中文注释：VideoSourcePlaybackLoading 是 VideoSourceRuntime 的播放页解析依赖。
protocol VideoSourcePlaybackLoading {
    func loadPlayback(
        _ input: SourceVideoPlaybackInput,
        definition: SourceDefinition
    ) async throws -> SourceVideoPlaybackOutput
}

// 中文注释：VideoSourcePlaybackLoader 负责加载播放页并提取候选媒体地址和播放上下文。
struct VideoSourcePlaybackLoader: VideoSourcePlaybackLoading {
    private let pageContentLoader: PageContentLoader
    private let mapper: any VideoContentMapper
    private let renderGuard: VideoHTMLRenderGuard
    private let requestConfigResolver: VideoRequestConfigResolver
    private let iframeMaxDepth: Int

    init(
        pageContentLoader: PageContentLoader,
        mapper: any VideoContentMapper,
        renderGuard: VideoHTMLRenderGuard = VideoHTMLRenderGuard(),
        requestConfigResolver: VideoRequestConfigResolver = VideoRequestConfigResolver(),
        iframeMaxDepth: Int = 2
    ) {
        self.pageContentLoader = pageContentLoader
        self.mapper = mapper
        self.renderGuard = renderGuard
        self.requestConfigResolver = requestConfigResolver
        self.iframeMaxDepth = iframeMaxDepth
    }

    func loadPlayback(
        _ input: SourceVideoPlaybackInput,
        definition: SourceDefinition
    ) async throws -> SourceVideoPlaybackOutput {
        guard let videoDefinition: VideoSourceDefinition = definition.video else {
            throw SourceRuntimeError.invalidInput("Video runtime requires a video source definition.")
        }

        let request: RequestConfig? = self.requestConfigResolver.request(
            for: .play,
            definition: videoDefinition,
            context: input.context
        )
        let html: String
        let renderIssues: [SourceRuntimeIssue]
        do {
            html = try await self.pageContentLoader.getString(from: input.playPageURL, request: request)
            renderIssues = try self.renderGuard.validateMappableHTML(url: input.playPageURL, html: html, request: request)
        } catch {
            throw self.requestConfigResolver.mappedLoadingError(error, url: input.playPageURL)
        }

        let initialReference: SourceVideoPlaybackReference = try self.mapper.mapPlayback(
            html: html,
            definition: definition,
            playPageURL: input.playPageURL
        )
        let iframePlayerResolution: VideoIframePlayerResolution? = try await VideoIframePlayerResolver(
            pageContentLoader: self.pageContentLoader,
            mapper: self.mapper,
            requestConfigResolver: self.requestConfigResolver,
            maxDepth: self.iframeMaxDepth
        ).resolve(
            reference: initialReference,
            definition: definition,
            baseRequest: request
        )
        let reference: SourceVideoPlaybackReference = iframePlayerResolution?.reference ?? initialReference
        let requestLogs: [SourceRequestLog] = [
            self.requestConfigResolver.requestLog(
                url: input.playPageURL,
                request: request,
                html: html
            )
        ] + (iframePlayerResolution?.requestLogs ?? [])
        let issues: [SourceRuntimeIssue] = renderIssues + (
            iframePlayerResolution?.issues
                ?? self.requestConfigResolver.playbackIssues(reference: reference)
        )

        return SourceVideoPlaybackOutput(
            reference: reference,
            diagnostics: SourceRuntimeDiagnostics.succeeded(
                requestLogs: requestLogs,
                issues: issues,
                context: SourceRuntimeDiagnosticContext(
                    runtimeContext: input.context,
                    requestURL: input.playPageURL
                )
            )
        )
    }
}
