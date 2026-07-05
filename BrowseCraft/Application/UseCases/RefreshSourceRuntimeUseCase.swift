import Foundation
import BrowseCraftCore

// 中文注释：RefreshSourceRuntimeUseCase 是按 SourceRuntimeKind 刷新列表的统一入口。
struct RefreshSourceRuntimeUseCase {
    private let runtimeResolver: any SourceRuntimeResolving

    init(
        runtimeResolver: any SourceRuntimeResolving
    ) {
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
        let output: SourceListOutput = try await runtime.loadList(input)
        #if DEBUG
        print(
            "[BrowseCraftRuntime] refresh output source=\(source.id) " +
            "kind=\(source.configuration.kind.rawValue) " +
            "items=\(output.items.count) " +
            "context=\(self.contextDescription(listContext))"
        )
        #endif
        return output
    }

    private func contextDescription(_ context: ListContext?) -> String {
        guard let context: ListContext = context else {
            return "nil"
        }

        return [
            "page=\(context.pageId ?? "nil")",
            "tab=\(context.tabId ?? "nil")",
            "section=\(context.sectionId ?? "nil")",
            "rule=\(context.listRuleId ?? "nil")"
        ].joined(separator: ",")
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
