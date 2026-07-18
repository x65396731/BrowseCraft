import Foundation
import BrowseCraftCore

/// 中文注释：漫画详情入口只依赖 SourceRuntime；具体规则加载和解析由 runtime 内部完成。
struct LoadComicDetailUseCase {
    private let runtimeResolver: any SourceRuntimeResolving
    private let itemReferenceMapper: SourceItemReferenceMapper = SourceItemReferenceMapper()

    init(runtimeResolver: any SourceRuntimeResolving) {
        self.runtimeResolver = runtimeResolver
    }

    func execute(source: Source, item: ContentItem) async throws -> SourceDetailOutput {
        guard let detailURL: URL = URL(string: item.detailURL) else {
            throw SourceRuntimeError.invalidInput("Invalid detail URL: \(item.detailURL)")
        }

        let runtime: any SourceRuntime = try self.runtimeResolver.runtime(for: source)
        return try await runtime.loadDetail(
            SourceDetailInput(
                detailURL: detailURL,
                context: SourceRuntimeContext(
                    sourceID: source.id,
                    pageID: item.listContext?.pageId,
                    tabID: item.listContext?.tabId,
                    sectionID: item.listContext?.sectionId,
                    sectionRole: item.listContext?.sectionRole?.rawValue,
                    ruleID: item.listContext?.listRuleId,
                    requestOverride: nil,
                    debugMode: false,
                    operation: .detail
                ),
                itemReference: self.itemReferenceMapper.reference(from: item, intent: .detail)
            )
        )
    }
}
