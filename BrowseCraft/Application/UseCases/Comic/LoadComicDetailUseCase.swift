import Foundation
import BrowseCraftCore

/// 中文注释：漫画详情入口依赖 Core 的详情能力协议；具体规则加载和解析由 runtime 内部完成。
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
        guard let detailRuntime: any SourceDetailRuntime = runtime as? any SourceDetailRuntime else {
            throw SourceRuntimeError.unsupported(
                .custom("Selected source does not expose detail runtime capability.")
            )
        }
        return try await detailRuntime.loadDetail(
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
