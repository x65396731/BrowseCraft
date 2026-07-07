import Foundation
import BrowseCraftCore
import BrowseCraftRulesKit

// 中文注释：BuiltInSource 声明应用随包来源，并为每个来源提供明确 runtime 配置。

/// 中文注释：应用随包提供的内置源。
/// 中文注释：内置源和用户源存放在同一个仓储中，稳定 ID 用于避免每次启动重复插入。
/// 中文注释：这里只负责声明内置来源；具体执行由对应 SourceRuntime 负责。
enum BuiltInSource {
    static let primaryBuiltInID: String = BrowseCraftPrivateRuleCatalog.primaryBuiltInID
    static let primaryBuiltInRuleJSON: String = BrowseCraftPrivateRuleCatalog.primaryBuiltInRuleJSON

    static func allBuiltIns(now: Date = Date()) -> [Source] {
        _ = now
        return []
    }

    /// 中文注释：primaryBuiltIn 方法返回默认漫画内置源；内部短期仍由 SiteRule 驱动。
    static func primaryBuiltIn(now: Date = Date()) -> Source {
        return Self.source(
            from: BrowseCraftBuiltInRule(
                id: Self.primaryBuiltInID,
                name: BrowseCraftPrivateRuleCatalog.primaryBuiltInName,
                baseURL: BrowseCraftPrivateRuleCatalog.primaryBuiltInBaseURL,
                ruleJSON: Self.primaryBuiltInRuleJSON
            ),
            now: now
        )
    }

    private static func source(from builtInRule: BrowseCraftBuiltInRule, now: Date) -> Source {
        return Source(
            id: builtInRule.id,
            name: builtInRule.name,
            baseURL: builtInRule.baseURL,
            type: .html,
            rule: Self.rule(from: builtInRule.ruleJSON),
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func rule(from ruleJSON: String) -> SiteRule {
        let ruleData: Data = Data(ruleJSON.utf8)

        do {
            return try JSONDecoder().decode(SiteRule.self, from: ruleData)
        } catch {
            // 中文注释：内置 JSON 属于应用包内容，解码失败代表开发期配置错误。
            fatalError("Invalid bundled rule JSON: \(error)")
        }
    }
}
