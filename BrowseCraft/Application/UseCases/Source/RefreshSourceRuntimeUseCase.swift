import Foundation
import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftLog
import BrowseCraftRuntime

// 中文注释：根据 Source 配置选择对应 runtime，并加载 Sources/Library 页面展示的列表内容。
struct ListContextTransfer: Sendable {
    let value: ListContext?
}

struct RefreshSourceRuntimeUseCase: Sendable {
    private let runtimeResolver: any SourceRuntimeResolving

    init(
        runtimeResolver: any SourceRuntimeResolving
    ) {
        self.runtimeResolver = runtimeResolver
    }

    func execute(
        source: Source,
        listContext: ListContextTransfer,
        page: Int = 1,
        debugMode: Bool = false
    ) async throws -> SourceListOutput {
        let context: ListContext? = listContext.value
        let runtime: any SourceRuntime = try self.runtimeResolver.runtime(for: source)
        let input: SourceListInput = self.listInput(
            source: source,
            listContext: context,
            page: page,
            debugMode: debugMode
        )
        // 中文注释：`BCA-RUNTIME-010`——第 1 页一条都没有或匹配不到内容时，换手机 UA 重做一次。
        let output: SourceListOutput = try await SourceUserAgentFallback.shared.perform(
            source: source,
            isEmpty: { (output: SourceListOutput) in page == 1 && output.items.isEmpty }
        ) {
            try await runtime.loadList(input)
        }
        #if DEBUG
        AppLog.debug(.rule, "runtime-refresh-output", [
            "source": .text("\(source.id)"),
            "kind": .text("\(source.configuration.kind.rawValue)"),
            "items": .text("\(output.items.count)"),
            "context": .text("\(self.contextDescription(context))")
        ])
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
