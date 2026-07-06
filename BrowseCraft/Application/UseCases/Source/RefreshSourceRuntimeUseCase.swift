import Foundation
import BrowseCraftCore

// 中文注释：根据 Source 配置选择对应 runtime，并加载 Sources/Library 页面展示的列表内容。
struct RefreshSourceRuntimeUseCase {
    private let runtimeResolver: any SourceRuntimeResolving
    private let sourcePresentationResolver: ResolveLibrarySourcePresentationUseCase

    init(
        runtimeResolver: any SourceRuntimeResolving,
        sourcePresentationResolver: ResolveLibrarySourcePresentationUseCase = ResolveLibrarySourcePresentationUseCase()
    ) {
        self.runtimeResolver = runtimeResolver
        self.sourcePresentationResolver = sourcePresentationResolver
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
                requestOverride: self.requestOverride(
                    source: source,
                    listContext: listContext
                ),
                debugMode: debugMode,
                operation: .list
            )
        )
    }

    private func requestOverride(
        source: Source,
        listContext: ListContext?
    ) -> SourceRequestOverride? {
        guard source.configuration.kind == .video,
              let tab: ListTabRule = self.videoListTab(source: source, listContext: listContext),
              let urlString: String = tab.list.url.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
              urlString.isEmpty == false,
              let url: URL = self.url(from: urlString, source: source) else {
            return nil
        }

        return SourceRequestOverride(
            url: url,
            headers: [:]
        )
    }

    private func videoListTab(
        source: Source,
        listContext: ListContext?
    ) -> ListTabRule? {
        let tabs: [ListTabRule] = self.sourcePresentationResolver.listTabs(for: source)

        if let tabID: String = listContext?.tabId,
           let tab: ListTabRule = tabs.first(where: { tab in
               return tab.id == tabID
           }) {
            return tab
        }

        if let listRuleID: String = listContext?.listRuleId,
           let tab: ListTabRule = tabs.first(where: { tab in
               return tab.list.id == listRuleID
           }) {
            return tab
        }

        return tabs.first
    }

    private func url(from string: String, source: Source) -> URL? {
        if let absoluteURL: URL = URL(string: string),
           absoluteURL.scheme != nil {
            return absoluteURL
        }

        guard let baseURL: URL = URL(string: source.baseURL) else {
            return URL(string: string)
        }

        return URL(string: string, relativeTo: baseURL)?.absoluteURL
    }
}

private extension String {
    var nonEmpty: String? {
        return self.isEmpty ? nil : self
    }
}
