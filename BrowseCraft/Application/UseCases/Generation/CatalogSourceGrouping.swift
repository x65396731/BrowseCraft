import BrowseCraftDomain
import Foundation

/// 目录列表的两个分组：网站默认数据（公共目录），与本人的生成结果（`/outcomes` 附带的规则）。
///
/// 中文注释：服务器的公共目录已经不含个人规则；个人规则来自 `/outcomes` 里成功任务的 `source`
/// （用例已解密为 `catalogSource`）。失败任务没有 source，但要说明原因（`reason` / `reasonDetail`）。
/// 到期与删除都由服务器裁决（7 天可见期、软删除），这里不再有本地隐藏集合。
struct CatalogSourceGrouping: Hashable, Sendable {
    let defaultSources: [CatalogSource]
    let personalSources: [CatalogSource]
    let failedOutcomes: [VideoGenerationOutcome]
    /// catalogSourceId → 该规则对应的成功终态（入口 URL、到期时间）。
    let personalOutcomes: [String: VideoGenerationOutcome]

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
        let personalIDs: Set<String> = Set(personalOutcomes.keys)
        // 中文注释：公共目录理论上不含个人规则；万一服务端旧版本还带着，也不在两组里重复显示。
        let defaultSources: [CatalogSource] = catalogSources.filter { source in
            return personalIDs.contains(source.id) == false
        }
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
            defaultSources: defaultSources,
            personalSources: personalSources,
            failedOutcomes: failedOutcomes,
            personalOutcomes: personalOutcomes
        )
    }
}
