import Foundation

// 中文注释：AddSourceUseCase.swift 属于应用用例层，用于说明本文件承载的核心职责。

/// 中文注释：根据 JSON 规则新增一个内容源。
/// 中文注释：该用例只负责创建 Source 的业务动作，不关心底层如何存储。
struct AddSourceUseCase {
    private let sourceRepository: SourceRepository
    private let jsonDecoder: JSONDecoder

    init(sourceRepository: SourceRepository, jsonDecoder: JSONDecoder = JSONDecoder()) {
        self.sourceRepository = sourceRepository
        self.jsonDecoder = jsonDecoder
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
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

