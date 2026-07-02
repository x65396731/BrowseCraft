import Foundation
import BrowseCraftRulesKit

// 中文注释：BuiltInSource.swift 属于领域模型层，用于说明本文件承载的核心职责。

/// 中文注释：应用随包提供的内置源。
/// 中文注释：内置源和用户源存放在同一个仓储中，稳定 ID 用于避免每次启动重复插入。
/// 中文注释：这里只负责加载内置规则，真正执行规则的是刷新源时的解析器。
enum BuiltInSource {
    static let primaryBuiltInID: String = BrowseCraftPrivateRuleCatalog.primaryBuiltInID
    static let primaryBuiltInRuleJSON: String = BrowseCraftPrivateRuleCatalog.primaryBuiltInRuleJSON

    /// 中文注释：primaryBuiltIn 方法封装当前类型的一段业务或界面行为。
    static func primaryBuiltIn(now: Date = Date()) -> Source {
        return Source(
            id: Self.primaryBuiltInID,
            name: BrowseCraftPrivateRuleCatalog.primaryBuiltInName,
            baseURL: BrowseCraftPrivateRuleCatalog.primaryBuiltInBaseURL,
            type: .html,
            rule: Self.primaryBuiltInRule(),
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func primaryBuiltInRule() -> SiteRule {
        let ruleData: Data = Data(Self.primaryBuiltInRuleJSON.utf8)

        do {
            return try JSONDecoder().decode(SiteRule.self, from: ruleData)
        } catch {
            // 中文注释：内置 JSON 属于应用包内容，解码失败代表开发期配置错误。
            fatalError("Invalid bundled rule JSON: \(error)")
        }
    }
}
