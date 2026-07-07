import Foundation
import BrowseCraftCore

// 中文注释：AddComicRuleSourceUseCase 是漫画网站规则导入路径；保存结果是 comic runtime 入口。

struct AddComicRuleSourceResult {
    let source: Source
    let listOutput: SourceListOutput
}

/// 中文注释：根据网站规则 JSON 新增一个由规则驱动的漫画 Source。
/// 中文注释：该用例是网站规则导入路径，不代表通用添加来源流程。
struct AddComicRuleSourceUseCase {
    private let sourceRepository: SourceRepository
    private let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase
    private let validateSourceListLoadUseCase: ValidateSourceListLoadUseCase
    private let jsonDecoder: JSONDecoder

    init(
        sourceRepository: SourceRepository,
        refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase,
        validateSourceListLoadUseCase: ValidateSourceListLoadUseCase = ValidateSourceListLoadUseCase(),
        jsonDecoder: JSONDecoder = JSONDecoder()
    ) {
        self.sourceRepository = sourceRepository
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
        self.validateSourceListLoadUseCase = validateSourceListLoadUseCase
        self.jsonDecoder = jsonDecoder
    }

    /// 中文注释：execute 方法先验证 comic runtime 能加载列表，成功后才保存 Source，并把加载结果交回 UI 复用。
    func execute(name: String, baseURL: String, ruleJSON: String) async throws -> AddComicRuleSourceResult {
        let ruleData: Data = Data(ruleJSON.utf8)
        let rule: SiteRule = try self.jsonDecoder.decode(SiteRule.self, from: ruleData)
        let now: Date = Date()

        let sourceName: String
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceName = rule.name
        } else {
            sourceName = name
        }

        let sourceBaseURL: String
        if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceBaseURL = rule.baseUrl
        } else {
            sourceBaseURL = baseURL
        }

        let source: Source = Source(
            id: UUID().uuidString,
            name: sourceName,
            baseURL: sourceBaseURL,
            type: .html,
            rule: rule,
            enabled: true,
            createdAt: now,
            updatedAt: now
        )

        let listOutput: SourceListOutput = try await self.refreshSourceRuntimeUseCase.execute(
            source: source,
            listContext: nil
        )
        try self.validateSourceListLoadUseCase.execute(listOutput)
        try self.sourceRepository.saveSource(source)
        return AddComicRuleSourceResult(source: source, listOutput: listOutput)
    }
}
