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
    private let parser: any VideoHTMLParsing

    init(
        pageContentLoader: PageContentLoader,
        parser: any VideoHTMLParsing
    ) {
        self.pageContentLoader = pageContentLoader
        self.parser = parser
    }

    func loadDetailContent(
        _ input: SourceDetailInput,
        definition: SourceDefinition
    ) async throws -> VideoDetailContent {
        let html: String = try await self.pageContentLoader.getString(from: input.detailURL)
        return try self.parser.parseDetail(
            html: html,
            definition: definition,
            detailURL: input.detailURL
        )
    }
}
