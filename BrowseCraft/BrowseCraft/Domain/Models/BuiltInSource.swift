import Foundation

// 中文注释：BuiltInSource.swift 属于领域模型层，用于说明本文件承载的核心职责。

/// 中文注释：应用随包提供的内置源。
/// 中文注释：内置源和用户源存放在同一个仓储中，稳定 ID 用于避免每次启动重复插入。
/// 中文注释：这里只负责加载内置规则，真正执行规则的是刷新源时的解析器。
enum BuiltInSource {
    static let myComicID: String = "built-in.mycomic"

    /// 中文注释：myComic 方法封装当前类型的一段业务或界面行为。
    static func myComic(now: Date = Date()) -> Source {
        return Source(
            id: Self.myComicID,
            name: "MYCOMIC",
            baseURL: "https://mycomic.com/cn",
            type: .html,
            rule: Self.myComicRule(),
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func myComicRule() -> SiteRule {
        let ruleData: Data = Data(SiteRule.myComicJSON.utf8)

        do {
            return try JSONDecoder().decode(SiteRule.self, from: ruleData)
        } catch {
            // 中文注释：内置 JSON 属于应用包内容，解码失败代表开发期配置错误。
            fatalError("Invalid bundled MYCOMIC rule JSON: \(error)")
        }
    }
}
