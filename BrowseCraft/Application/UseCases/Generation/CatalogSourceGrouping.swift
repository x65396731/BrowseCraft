import BrowseCraftDomain
import Foundation

/// 目录列表的两个分组：「发现」（公共目录按 `section` 筛过），与本人的生成结果（`/outcomes` 附带的规则）。
///
/// 中文注释：服务器的公共目录已经不含个人规则；个人规则来自 `/outcomes` 里成功任务的 `source`
/// （用例已解密为 `catalogSource`）。失败任务没有 source，但要说明原因（`reason` / `reasonDetail`）。
/// 到期与删除都由服务器裁决（7 天可见期、软删除），这里不再有本地隐藏集合。
///
/// 「发现」只收两种分区（`docs/design/Catalog-Page-Redesign-Design.md` 2.2）：`example` 最多 6 条、保持服务端顺序；
/// `internal` 只在 Debug 构建收进来，Release 构建没有取用它的代码路径。没有 `section` 或取值不认得的条目不展示。
struct CatalogSourceGrouping: Hashable, Sendable {
    static let maximumExampleCount: Int = 6

    let exampleSources: [CatalogSource]
    /// 内部测试站点；Release 构建恒为空。
    let internalSources: [CatalogSource]
    let personalSources: [CatalogSource]
    let failedOutcomes: [VideoGenerationOutcome]
    /// catalogSourceId → 该规则对应的成功终态（入口 URL、到期时间）。
    let personalOutcomes: [String: VideoGenerationOutcome]
    /// catalogSourceId → 公共目录里「同一主机有多条来源」时各自规则的入口 URL。
    ///
    /// 中文注释：同站多入口（sfacg「全部小说」与分类 tid=21、动漫嗨手写与生成）名字与 `baseURL` 都相同，
    /// 目录行无从区分；只对这种来源给出入口，单独一条的站保持显示 `baseURL`。
    var defaultEntryURLs: [String: String] = [:]

    /// 「发现」里展示的全部公共条目。
    var defaultSources: [CatalogSource] {
        return self.exampleSources + self.internalSources
    }

    var personalEntryURLs: [String: String] {
        return self.personalOutcomes.compactMapValues { $0.entryURL }
    }

    static func make(
        catalogSources: [CatalogSource],
        outcomes: [VideoGenerationOutcome]
    ) -> CatalogSourceGrouping {
        var personalSources: [CatalogSource] = []
        var personalOutcomes: [String: VideoGenerationOutcome] = [:]
        for outcome in outcomes where outcome.didSucceed {
            guard let source: CatalogSource = outcome.catalogSource,
                  personalOutcomes[source.id] == nil else {
                continue
            }
            personalSources.append(source)
            personalOutcomes[source.id] = outcome
        }
        // 中文注释：不按本人生成 id 剔除公共条目——「发现」只收带 section 的条目，个人规则没有 section 本就进不来；
        // 而示例可以由用户生成的规则转来，剔除会让生成者本人在 7 天可见期内看不到这条示例（2026-10-22 真机：3 条只显示 1 条）。
        let exampleSources: [CatalogSource] = Array(
            catalogSources.filter { source in source.section == .example }.prefix(Self.maximumExampleCount)
        )
        #if DEBUG
        let internalSources: [CatalogSource] = catalogSources.filter { source in source.section == .internalTest }
        #else
        let internalSources: [CatalogSource] = []
        #endif
        // 中文注释：同一入口 URL 只保留最近一次失败——服务端按终结时间倒序返回，取首个。
        var seenEntryURLs: Set<String> = []
        var failedOutcomes: [VideoGenerationOutcome] = []
        for outcome in outcomes where outcome.didSucceed == false {
            let key: String = outcome.entryURL ?? outcome.jobID.uuidString
            if seenEntryURLs.insert(key).inserted {
                failedOutcomes.append(outcome)
            }
        }
        return CatalogSourceGrouping(
            exampleSources: exampleSources,
            internalSources: internalSources,
            personalSources: personalSources,
            failedOutcomes: failedOutcomes,
            personalOutcomes: personalOutcomes,
            defaultEntryURLs: Self.sameHostEntryURLs(exampleSources + internalSources)
        )
    }

    /// 中文注释：按主机分组，一个主机出现两条及以上时，逐条取规则里的入口 URL；取不到的不写，视图退回 `baseURL`。
    private static func sameHostEntryURLs(_ sources: [CatalogSource]) -> [String: String] {
        var sourcesByHost: [String: [CatalogSource]] = [:]
        for source in sources {
            guard let host: String = URL(string: source.baseURL)?.host?.lowercased() else {
                continue
            }
            sourcesByHost[host, default: []].append(source)
        }
        var entryURLs: [String: String] = [:]
        for group in sourcesByHost.values where group.count > 1 {
            for source in group {
                if let entryURL: String = Self.ruleEntryURL(ruleJSON: source.ruleJSON, baseURL: source.baseURL) {
                    entryURLs[source.id] = entryURL
                }
            }
        }
        return entryURLs
    }

    /// 规则 `pages[]` 里第一个可展示的入口：跳过缺失与带占位符的模板（`?page={page}`），相对路径按 `baseURL` 补全。
    static func ruleEntryURL(ruleJSON: String, baseURL: String) -> String? {
        guard let data: Data = ruleJSON.data(using: .utf8),
              let object: [String: Any] = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let pages: [[String: Any]] = object["pages"] as? [[String: Any]] else {
            return nil
        }
        for page in pages {
            guard let rawURL: String = page["url"] as? String,
                  rawURL.isEmpty == false,
                  rawURL.contains("{") == false,
                  let resolved: URL = URL(string: rawURL, relativeTo: URL(string: baseURL)) else {
                continue
            }
            return resolved.absoluteURL.absoluteString
        }
        return nil
    }
}
