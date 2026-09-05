import Foundation
import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime

/// 中文注释：来源内搜索（`BC-SEARCH-007` 的 App 侧）：由规则声明能力，App 只解释规则、不猜 URL。
/// 搜索结果与列表同型（`SourceListOutput`），后续详情/剧集/播放链完全复用。
struct SearchSourceContentUseCase: Sendable {
    private let runtimeResolver: any SourceRuntimeResolving

    init(runtimeResolver: any SourceRuntimeResolving) {
        self.runtimeResolver = runtimeResolver
    }

    /// 规则没有声明搜索时返回 false，界面据此不显示搜索入口。
    func supportsSearch(source: Source) -> Bool {
        guard let runtime: any SourceRuntime = try? self.runtimeResolver.runtime(for: source) else {
            return false
        }
        return runtime.capabilities.supportsSearch && runtime is SourceSearchRuntime
    }

    func execute(source: Source, keyword: String, page: Int = 1) async throws -> SourceListOutput {
        let runtime: any SourceRuntime = try self.runtimeResolver.runtime(for: source)
        guard let searchRuntime: any SourceSearchRuntime = runtime as? SourceSearchRuntime,
              runtime.capabilities.supportsSearch else {
            throw SourceRuntimeError.unsupported(.custom("This source does not declare a search rule."))
        }
        let input: SourceSearchInput = SourceSearchInput(
            keyword: keyword,
            page: page,
            urlOverride: nil,
            context: SourceRuntimeContext(
                sourceID: source.id,
                pageID: nil,
                tabID: nil,
                ruleID: nil,
                requestOverride: nil,
                debugMode: false,
                operation: .search
            )
        )
        return try await searchRuntime.search(input)
    }
}
