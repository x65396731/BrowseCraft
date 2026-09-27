import Foundation

/// 服务端账户快照：coin 余额、版本号与价格（设计书 `video-pending-and-frozen-designs.md` 30.6）。
struct PortalAccountSnapshot: Hashable, Sendable {
    let userID: UUID
    let coinBalance: Int
    let revision: Int
    let pricing: CoinPricing
}

/// 中文注释：价格由服务端下发，App 只在还没拿到时用这组缺省值显示；不参与任何扣费判断。
struct CoinPricing: Hashable, Sendable {
    let normal: Int
    let hard: Int
    let adReward: Int

    static let placeholder: CoinPricing = CoinPricing(normal: 100, hard: 300, adReward: 20)
}

enum PortalAccountClientError: Error, Hashable, Sendable {
    case authRequired
    case transport
    case server(code: String)
}

/// coin 流水一条（设计书 30.8）：服务端只下发原因、增减、记账后余额与时间。
struct CoinLedgerEntry: Hashable, Sendable, Identifiable {
    let id: String
    let delta: Int
    let reason: CoinLedgerReason
    let balanceAfter: Int
    let createdAt: Date
}

/// 流水原因；服务端新增取值时旧 App 落到 `.unknown`。
enum CoinLedgerReason: Hashable, Sendable {
    case signupGrant
    case adReward
    case generationNormal
    case generationHard
    case zeroCostRefund
    case manualAdjustment
    case unknown(String)
}

struct CoinLedgerPage: Hashable, Sendable {
    let entries: [CoinLedgerEntry]
    let nextCursor: String?
}

/// 读账户快照与流水的 Application 端口；实现是 APIKit 适配器，只在组合根出现。
protocol PortalAccountFetching: Sendable {
    func fetchAccount(accessToken: String) async throws -> PortalAccountSnapshot
    /// 时间倒序一页；`cursor` 为上一页的 `nextCursor`，nil 从最新开始。
    func fetchLedger(accessToken: String, cursor: String?) async throws -> CoinLedgerPage
}
