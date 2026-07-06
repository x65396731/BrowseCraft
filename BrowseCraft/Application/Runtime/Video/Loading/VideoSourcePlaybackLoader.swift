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
    private let parser: any VideoHTMLParsing

    init(
        pageContentLoader: PageContentLoader,
        parser: any VideoHTMLParsing
    ) {
        self.pageContentLoader = pageContentLoader
        self.parser = parser
    }

    func loadPlayback(
        _ input: SourceVideoPlaybackInput,
        definition: SourceDefinition
    ) async throws -> SourceVideoPlaybackOutput {
        let html: String = try await self.pageContentLoader.getString(from: input.playPageURL)
        let reference: SourceVideoPlaybackReference = try self.parser.parsePlayback(
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
