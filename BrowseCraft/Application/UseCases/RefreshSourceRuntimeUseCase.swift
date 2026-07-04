import Foundation
import BrowseCraftCore

// 中文注释：Runtime-facing 列表刷新入口；P3-7.4 先作为并行 use case，不替换 Library 调用链。
struct RefreshSourceRuntimeUseCase {
    private let runtimeResolver: any SourceRuntimeResolving

    init(runtimeResolver: any SourceRuntimeResolving) {
        self.runtimeResolver = runtimeResolver
    }

    func execute(
        source: Source,
        listContext: ListContext?,
        page: Int = 1,
        debugMode: Bool = false
    ) async throws -> SourceListOutput {
        let runtime: any SourceRuntime = try self.runtimeResolver.runtime(for: source)
        let input: SourceListInput = self.listInput(
            source: source,
            listContext: listContext,
            page: page,
            debugMode: debugMode
        )
        return try await runtime.loadList(input)
    }

    private func listInput(
        source: Source,
        listContext: ListContext?,
        page: Int,
        debugMode: Bool
    ) -> SourceListInput {
        return SourceListInput(
            page: page,
            urlOverride: nil,
            context: SourceRuntimeContext(
                sourceID: source.id,
                pageID: listContext?.pageId,
                tabID: listContext?.tabId,
                sectionID: listContext?.sectionId,
                sectionRole: listContext?.sectionRole?.rawValue,
                ruleID: listContext?.listRuleId,
                requestOverride: nil,
                debugMode: debugMode,
                operation: .list
            )
        )
    }
}
