import Foundation

/// 个人规则在本地的回执：第一次出现在「我的生成」的时刻，保留期从这一刻起算。
struct PersonalRuleReceipt: Hashable, Sendable {
    let catalogSourceID: String
    let receivedAt: Date
}

/// 个人规则回执与本地删除记录的存储端口（按用户隔离）。
///
/// 中文注释：只存 catalogSourceId / jobId 与时间，不存规则内容；服务器目录是共享的，
/// 「删除」与「到期」都只是本地隐藏 + 删本地副本，不向服务器发请求。
protocol PersonalRuleReceiptStoring: Sendable {
    func receipts(userID: String) -> [PersonalRuleReceipt]
    /// 已有回执时不覆盖——保留期以第一次收到为准。
    func recordReceiptIfAbsent(catalogSourceID: String, userID: String, receivedAt: Date)
    func hiddenIDs(userID: String) -> Set<String>
    func hide(id: String, userID: String)
}
