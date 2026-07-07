import Foundation
import BrowseCraftCore

// 中文注释：VideoSourceListLoading 是 VideoSourceRuntime 的列表加载依赖，便于后续替换不同站点策略。
protocol VideoSourceListLoading {
    func loadList(
        _ input: SourceListInput,
        definition: SourceDefinition
    ) async throws -> SourceListOutput
}

// 中文注释：VideoSourceListLoader 负责 video source 的列表 URL 选择、页面加载和列表映射。
struct VideoSourceListLoader: VideoSourceListLoading {
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

    func loadList(
        _ input: SourceListInput,
        definition: SourceDefinition
    ) async throws -> SourceListOutput {
        let url: URL = try self.listURL(for: input, definition: definition)
        guard let videoDefinition: VideoSourceDefinition = definition.video else {
            throw SourceRuntimeError.invalidInput("Video runtime requires a video source definition.")
        }

        let request: RequestConfig? = self.requestConfigResolver.request(
            for: .list,
            definition: videoDefinition,
            context: input.context
        )
        let html: String
        do {
            html = try await self.pageContentLoader.getString(from: url, request: request)
            try self.renderingGuard.validateStaticHTML(url: url, html: html)
        } catch {
            throw self.requestConfigResolver.mappedLoadingError(error, url: url)
        }

        let items: [SourceContentItem] = try self.mapper.mapList(
            html: html,
            definition: definition,
            pageURL: url
        )

        return SourceListOutput(
            items: items,
            pagination: nil,
            diagnostics: SourceRuntimeDiagnostics.succeeded(
                requestLogs: [
                    self.requestConfigResolver.requestLog(
                        url: url,
                        request: request,
                        html: html
                    )
                ],
                issues: self.requestConfigResolver.emptyListIssues(items: items),
                context: SourceRuntimeDiagnosticContext(
                    runtimeContext: input.context,
                    requestURL: url
                )
            )
        )
    }

    private func listURL(
        for input: SourceListInput,
        definition: SourceDefinition
    ) throws -> URL {
        if let urlOverride: URL = input.urlOverride {
            return urlOverride
        }

        if let requestOverrideURL: URL = input.context.requestOverride?.url {
            return requestOverrideURL
        }

        return try self.entryURL(definition: definition)
    }

    private func entryURL(definition: SourceDefinition) throws -> URL {
        guard let videoDefinition: VideoSourceDefinition = definition.video else {
            throw SourceRuntimeError.invalidInput("Video runtime requires a video source definition.")
        }

        return videoDefinition.entryURL
    }
}
