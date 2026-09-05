import BrowseCraftDomain
import Foundation

/// 目录列表的两个分组：网站默认数据，与按当前用户的生成结果挑出的个人数据。
///
/// 中文注释：服务端 `/catalog/sources` 是全站一份、不分用户；哪些属于「我的」只能由
/// `/outcomes` 里成功任务的 `catalogSourceId` 决定。失败的任务没有 source，但要在个人
/// 分组里说明原因（`reason` / `reasonDetail`），否则用户只看到推送、看不到结果。
struct CatalogSourceGrouping: Hashable, Sendable {
    let defaultSources: [CatalogSource]
    let personalSources: [CatalogSource]
    let failedOutcomes: [VideoGenerationOutcome]

    static func make(
        catalogSources: [CatalogSource],
        outcomes: [VideoGenerationOutcome]
    ) -> CatalogSourceGrouping {
        let personalIDs: Set<String> = Set(
            outcomes.compactMap { outcome in
                return outcome.didSucceed ? outcome.catalogSourceID : nil
            }
        )
        let personalSources: [CatalogSource] = catalogSources.filter { source in
            return personalIDs.contains(source.id)
        }
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
            failedOutcomes: failedOutcomes
        )
    }
}
