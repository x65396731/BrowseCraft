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
    /// 个人规则的入口 URL（catalogSourceId → entryURL），用于和默认数据里同站的规则区分。
    let personalEntryURLs: [String: String]

    /// `hiddenIDs`：用户删除或已到期的个人规则（catalogSourceId）与失败记录（jobId），
    /// 两组都不再显示——服务器目录仍有它，但对这个用户它已经「删掉」了。
    static func make(
        catalogSources: [CatalogSource],
        outcomes: [VideoGenerationOutcome],
        hiddenIDs: Set<String> = []
    ) -> CatalogSourceGrouping {
        var personalEntryURLs: [String: String] = [:]
        for outcome in outcomes where outcome.didSucceed {
            if let catalogSourceID: String = outcome.catalogSourceID,
               let entryURL: String = outcome.entryURL,
               personalEntryURLs[catalogSourceID] == nil {
                personalEntryURLs[catalogSourceID] = entryURL
            }
        }
        let personalIDs: Set<String> = Set(personalEntryURLs.keys).union(
            outcomes.compactMap { outcome in
                return outcome.didSucceed ? outcome.catalogSourceID : nil
            }
        )
        let personalSources: [CatalogSource] = catalogSources.filter { source in
            return personalIDs.contains(source.id) && hiddenIDs.contains(source.id) == false
        }
        let defaultSources: [CatalogSource] = catalogSources.filter { source in
            return personalIDs.contains(source.id) == false && hiddenIDs.contains(source.id) == false
        }
        // 中文注释：同一入口 URL 只保留最近一次失败——服务端按终结时间倒序返回，取首个。
        var seenEntryURLs: Set<String> = []
        var failedOutcomes: [VideoGenerationOutcome] = []
        for outcome in outcomes where outcome.didSucceed == false {
            if hiddenIDs.contains(outcome.jobID.uuidString) {
                continue
            }
            let key: String = outcome.entryURL ?? outcome.jobID.uuidString
            if seenEntryURLs.insert(key).inserted {
                failedOutcomes.append(outcome)
            }
        }
        return CatalogSourceGrouping(
            defaultSources: defaultSources,
            personalSources: personalSources,
            failedOutcomes: failedOutcomes,
            personalEntryURLs: personalEntryURLs
        )
    }
}
