import BrowseCraftDomain
import Foundation

/// 从目录规则本体里取给用户看的信息：分类、能否搜索、语言。
///
/// 中文注释：目录接口只给 id / name / baseURL / kind / ruleJSON，推荐卡片能多展示的只能来自规则本体。
/// 三种 kind 的规则在这几处用同一套路径（`pages[].title`、`ruleSets.searchRules`、`site.language`），
/// 因此按 JSON 路径读、不按 kind 分支，也不经 Core 的严格校验——这里只取展示信息，规则合不合法由添加路径裁决。
/// 2026-09-30 线上 23 条规则实测：≥2 个分类 15 条、可搜索 13 条、有语言 21 条、有站点图标 0 条——
/// 所以卡片展示前三项，图标不取；登录需求（`site.loginURL`）按用户裁定不展示，这里也不取。
struct CatalogRuleFacts: Hashable, Sendable {
    /// 可浏览的列表页标题（`list` / `category` / `series`），按规则里的顺序，去重、去空。
    let categoryTitles: [String]
    let supportsSearch: Bool
    /// 规则声明的语言原值（如 `zh-Hans`、`cmn-Hant-TW`、`ja`）；归一在 `CatalogLanguage`。
    let language: String?

    static let browsablePageTypes: Set<String> = ["list", "category", "series"]

    static func makeIndex(_ catalogSources: [CatalogSource]) -> [String: CatalogRuleFacts] {
        var index: [String: CatalogRuleFacts] = [:]
        for catalogSource: CatalogSource in catalogSources {
            index[catalogSource.id] = Self.make(ruleJSON: catalogSource.ruleJSON)
        }
        return index
    }

    static func make(ruleJSON: String) -> CatalogRuleFacts? {
        guard let data: Data = ruleJSON.data(using: .utf8),
              let root: [String: Any] = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var titles: [String] = []
        for page: [String: Any] in (root["pages"] as? [[String: Any]]) ?? [] {
            guard let type: String = page["type"] as? String, Self.browsablePageTypes.contains(type),
                  let title: String = (page["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  title.isEmpty == false, titles.contains(title) == false else {
                continue
            }
            titles.append(title)
        }

        let ruleSets: [String: Any] = (root["ruleSets"] as? [String: Any]) ?? [:]
        let searchRules: [Any] = (ruleSets["searchRules"] as? [Any]) ?? []
        let site: [String: Any] = (root["site"] as? [String: Any]) ?? [:]
        let language: String? = (site["language"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        return CatalogRuleFacts(
            categoryTitles: titles,
            supportsSearch: searchRules.isEmpty == false,
            language: language?.isEmpty == false ? language : nil
        )
    }

    /// 卡片上的分类行：前 `limit` 个用「 · 」连起来，其余写「+N」；没有分类时为 nil。
    func categorySummary(limit: Int = 3) -> String? {
        guard self.categoryTitles.isEmpty == false else {
            return nil
        }
        let shown: String = self.categoryTitles.prefix(limit).joined(separator: " · ")
        let rest: Int = self.categoryTitles.count - limit
        return rest > 0 ? "\(shown) +\(rest)" : shown
    }
}

/// 规则语言的归一与显示。
///
/// 中文注释：线上同是中文就有 `zh-Hans`、`zh-Hant`、`cmn-Hans-HK`、`cmn-Hant-TW` 四种写法，不归一的话
/// 「繁中」会因为写法不同被当成两种语言。中文按文字（简 / 繁）区分：显式 script 优先，没有时按地区推断
/// （台港澳为繁）；其余语言只看语言代码。
enum CatalogLanguage: Hashable {
    case chinese(traditional: Bool)
    case other(code: String)

    static let traditionalChineseRegions: Set<String> = ["TW", "HK", "MO"]

    init?(identifier: String) {
        let parts: [String] = identifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map(String.init)
        guard let first: String = parts.first?.lowercased(), first.isEmpty == false else {
            return nil
        }
        guard first == "zh" || first == "cmn" else {
            self = .other(code: first)
            return
        }
        let rest: [String] = parts.dropFirst().map { $0 }
        if let script: String = rest.first(where: { $0.count == 4 })?.lowercased() {
            self = .chinese(traditional: script == "hant")
        } else {
            let region: String? = rest.first(where: { $0.count == 2 })?.uppercased()
            self = .chinese(traditional: region.map { Self.traditionalChineseRegions.contains($0) } ?? false)
        }
    }

    /// 卡片上的语言标签。与 App 当前界面语言相同时返回 nil——只标出「和我不一样」的站。
    static func tag(for identifier: String, appLanguage: String) -> String? {
        guard let language: CatalogLanguage = CatalogLanguage(identifier: identifier) else {
            return nil
        }
        if let app: CatalogLanguage = CatalogLanguage(identifier: appLanguage), app == language {
            return nil
        }
        switch language {
        case .chinese(let traditional):
            return NSLocalizedString(
                traditional ? "catalog_language_traditional_chinese" : "catalog_language_simplified_chinese",
                comment: ""
            )
        case .other(let code):
            return Locale(identifier: appLanguage).localizedString(forLanguageCode: code) ?? code
        }
    }

    /// App 当前实际使用的界面语言（三份 Localizable 中的哪一份）。
    static var appLanguage: String {
        return Bundle.main.preferredLocalizations.first ?? "en"
    }
}
