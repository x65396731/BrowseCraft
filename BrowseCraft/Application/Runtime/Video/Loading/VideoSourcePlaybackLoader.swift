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
    private let mapper: any VideoHTMLMapper
    private let renderingGuard: VideoSourceRenderingGuard

    init(
        pageContentLoader: PageContentLoader,
        mapper: any VideoHTMLMapper,
        renderingGuard: VideoSourceRenderingGuard = VideoSourceRenderingGuard()
    ) {
        self.pageContentLoader = pageContentLoader
        self.mapper = mapper
        self.renderingGuard = renderingGuard
    }

    func loadPlayback(
        _ input: SourceVideoPlaybackInput,
        definition: SourceDefinition
    ) async throws -> SourceVideoPlaybackOutput {
        let html: String = try await self.pageContentLoader.getString(from: input.playPageURL)
        try self.renderingGuard.validateStaticHTML(url: input.playPageURL, html: html)
        let reference: SourceVideoPlaybackReference = try self.mapper.mapPlayback(
            html: html,
            definition: definition,
            playPageURL: input.playPageURL
        )

        return SourceVideoPlaybackOutput(
            reference: reference,
            diagnostics: SourceRuntimeDiagnostics.succeeded(
                context: SourceRuntimeDiagnosticContext(
                    runtimeContext: input.context,
                    requestURL: input.playPageURL
                )
            )
        )
    }
}
