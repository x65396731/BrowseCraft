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

/// 读账户快照的 Application 端口；实现是 APIKit 适配器，只在组合根出现。
protocol PortalAccountFetching: Sendable {
    func fetchAccount(accessToken: String) async throws -> PortalAccountSnapshot
}
