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
    private let mapper: any VideoContentMapper
    private let renderGuard: VideoHTMLRenderGuard
    private let requestConfigResolver: VideoRequestConfigResolver

    init(
        pageContentLoader: PageContentLoader,
        mapper: any VideoContentMapper,
        renderGuard: VideoHTMLRenderGuard = VideoHTMLRenderGuard(),
        requestConfigResolver: VideoRequestConfigResolver = VideoRequestConfigResolver()
    ) {
        self.pageContentLoader = pageContentLoader
        self.mapper = mapper
        self.renderGuard = renderGuard
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

        if videoDefinition.entryKind == .play {
            return VideoDetailContent(
                episodes: [
                    VideoEpisode(
                        id: "\(definition.id).video.single.\(self.stableID(from: input.detailURL))",
                        title: definition.name,
                        playPageURL: input.detailURL
                    )
                ],
                synopsis: nil,
                metadataRows: [],
                requestLogs: [
                    self.requestConfigResolver.requestLog(
                        url: input.detailURL,
                        request: request
                    )
                ],
                issues: []
            )
        }

        let html: String
        let renderIssues: [SourceRuntimeIssue]
        do {
            html = try await self.pageContentLoader.getString(from: input.detailURL, request: request)
            renderIssues = try self.renderGuard.validateMappableHTML(url: input.detailURL, html: html, request: request)
        } catch {
            throw self.requestConfigResolver.mappedLoadingError(error, url: input.detailURL)
        }

        var content: VideoDetailContent = try self.mapper.mapDetail(
            html: html,
            definition: definition,
            detailURL: input.detailURL
        )
        content.requestLogs = [
            self.requestConfigResolver.requestLog(
                url: input.detailURL,
                request: request,
                html: html
            )
        ]
        content.issues = renderIssues

        return content
    }

    private func stableID(from url: URL) -> String {
        let value: String = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/", with: "-")

        return value.isEmpty ? "root" : value
    }
}
