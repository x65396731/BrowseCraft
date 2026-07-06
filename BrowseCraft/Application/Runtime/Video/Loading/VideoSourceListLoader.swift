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

    init(
        pageContentLoader: PageContentLoader,
        mapper: any VideoHTMLMapper
    ) {
        self.pageContentLoader = pageContentLoader
        self.mapper = mapper
    }

    func loadList(
        _ input: SourceListInput,
        definition: SourceDefinition
    ) async throws -> SourceListOutput {
        let url: URL = try self.listURL(for: input, definition: definition)
        let html: String = try await self.pageContentLoader.getString(from: url)
        let items: [SourceContentItem] = try self.mapper.mapList(
            html: html,
            definition: definition,
            pageURL: url
        )

        return SourceListOutput(
            items: items,
            pagination: nil,
            diagnostics: SourceRuntimeDiagnostics.succeeded(
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

        if let tabURL: URL = try self.listTabURL(
            for: input.context,
            definition: definition
        ) {
            return tabURL
        }

        return try self.entryURL(definition: definition)
    }

    private func listTabURL(
        for context: SourceRuntimeContext,
        definition: SourceDefinition
    ) throws -> URL? {
        let identifier: String? = context.ruleID ?? context.tabID
        guard let identifier: String = identifier else {
            return nil
        }

        let definitionEntryURL: URL = try self.entryURL(definition: definition)
        if identifier == "video.home" {
            return definitionEntryURL
        }

        guard identifier.hasPrefix("video.category."),
              let categoryID: String = identifier.split(separator: ".").last.map(String.init) else {
            return nil
        }

        return URL(
            string: "/vodtype/\(categoryID).html",
            relativeTo: definitionEntryURL
        )?.absoluteURL
    }

    private func entryURL(definition: SourceDefinition) throws -> URL {
        guard let videoDefinition: VideoSourceDefinition = definition.video else {
            throw SourceRuntimeError.invalidInput("Video runtime requires a video source definition.")
        }

        return videoDefinition.entryURL
    }
}
