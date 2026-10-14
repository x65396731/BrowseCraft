import Foundation

/// 中文注释：StoreKit 读到的拥有属于手机上的 App Store 账户；这条规则判断它是否已被当前 AnyPortal 账号认领
/// （docs/design/Account-Deletion-Design.md 第 9.2 节）。三条任一满足即算认领：交易记的就是当前账号；本机当前账号已有
/// 这笔交易的处理记录（购买、恢复成功时写入）；本次会话服务端回的权益包含该商品。都不满足时购买页显示「需要恢复」。
enum StoreKitPurchaseClaimRule {
    static func isClaimed(
        appAccountToken: UUID?,
        activeUserID: UUID,
        hasLocalRecord: Bool,
        isPortalEntitled: Bool
    ) -> Bool {
        return appAccountToken == activeUserID || hasLocalRecord || isPortalEntitled
    }
}
