import Foundation
import BrowseCraftCore

// 中文注释：VideoSourceDetailLoading 是 VideoSourceRuntime 的详情加载依赖，输出包含剧集和详情文案。
protocol VideoSourceDetailLoading {
    func loadDetailContent(
        _ input: SourceDetailInput,
        definition: SourceDefinition
    ) async throws -> VideoDetailContent
}

// 中文注释：VideoSourceDetailLoader 负责加载详情页并映射剧集、简介和元信息。
struct VideoSourceDetailLoader: VideoSourceDetailLoading {
    private let pageContentLoader: PageContentLoader
    private let mapper: any VideoHTMLMapper
    private let renderingGuard: VideoSourceRenderingGuard
    private let requestConfigResolver: VideoRequestConfigResolver

    init(
        pageContentLoader: PageContentLoader,
        mapper: any VideoHTMLMapper,
        renderingGuard: VideoSourceRenderingGuard = VideoSourceRenderingGuard(),
        requestConfigResolver: VideoRequestConfigResolver = VideoRequestConfigResolver()
    ) {
        self.pageContentLoader = pageContentLoader
        self.mapper = mapper
        self.renderingGuard = renderingGuard
        self.requestConfigResolver = requestConfigResolver
    }

    func loadDetailContent(
        _ input: SourceDetailInput,
        definition: SourceDefinition
    ) async throws -> VideoDetailContent {
        guard let videoDefinition: VideoSourceDefinition = definition.video else {
            throw SourceRuntimeError.invalidInput("Video runtime requires a video source definition.")
        }

        let request: RequestConfig? = self.requestConfigResolver.request(
            for: .detail,
            definition: videoDefinition,
            context: input.context
        )
        let html: String
        do {
            html = try await self.pageContentLoader.getString(from: input.detailURL, request: request)
            try self.renderingGuard.validateStaticHTML(url: input.detailURL, html: html)
        } catch {
            throw self.requestConfigResolver.mappedLoadingError(error, url: input.detailURL)
        }

        return try self.mapper.mapDetail(
            html: html,
            definition: definition,
            detailURL: input.detailURL
        )
    }
}
