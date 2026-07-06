import Foundation

// 中文注释：AddComicRuleSourceUseCase 是漫画网站规则导入路径；保存结果是 comic runtime 入口。

/// 中文注释：根据网站规则 JSON 新增一个由规则驱动的漫画 Source。
/// 中文注释：该用例是网站规则导入路径，不代表通用添加来源流程。
struct AddComicRuleSourceUseCase {
    private let sourceRepository: SourceRepository
    private let jsonDecoder: JSONDecoder

    init(sourceRepository: SourceRepository, jsonDecoder: JSONDecoder = JSONDecoder()) {
        self.sourceRepository = sourceRepository
        self.jsonDecoder = jsonDecoder
    }

    /// 中文注释：execute 方法执行网站规则导入，并保存为 comic runtime 入口的 Source。
    func execute(name: String, baseURL: String, ruleJSON: String) throws -> Source {
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

        try self.sourceRepository.saveSource(source)
        return source
    }
}
