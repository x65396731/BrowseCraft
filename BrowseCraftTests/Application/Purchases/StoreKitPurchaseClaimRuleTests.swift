import Foundation
import Testing
@testable import BrowseCraft

/// docs/design/Account-Deletion-Design.md 第 9.2 节：StoreKit 拥有是否已被当前账号认领。
struct StoreKitPurchaseClaimRuleTests {
    private let activeUserID: UUID = UUID()

    @Test func ownPurchaseIsClaimedWithoutAnyRecord() {
        #expect(StoreKitPurchaseClaimRule.isClaimed(
            appAccountToken: self.activeUserID, activeUserID: self.activeUserID,
            hasLocalRecord: false, isPortalEntitled: false
        ))
    }

    @Test func purchaseFromDeletedAccountNeedsRestoreUntilClaimed() {
        let deletedAccount: UUID = UUID()
        #expect(StoreKitPurchaseClaimRule.isClaimed(
            appAccountToken: deletedAccount, activeUserID: self.activeUserID,
            hasLocalRecord: false, isPortalEntitled: false
        ) == false)
        // 中文注释：恢复成功后，本次会话靠服务端权益、之后靠本机处理记录认作已认领——不会每次打开购买页又显示「需要恢复」。
        #expect(StoreKitPurchaseClaimRule.isClaimed(
            appAccountToken: deletedAccount, activeUserID: self.activeUserID,
            hasLocalRecord: false, isPortalEntitled: true
        ))
        #expect(StoreKitPurchaseClaimRule.isClaimed(
            appAccountToken: deletedAccount, activeUserID: self.activeUserID,
            hasLocalRecord: true, isPortalEntitled: false
        ))
    }

    @Test func purchaseWithoutTokenNeedsRestore() {
        #expect(StoreKitPurchaseClaimRule.isClaimed(
            appAccountToken: nil, activeUserID: self.activeUserID,
            hasLocalRecord: false, isPortalEntitled: false
        ) == false)
    }
}
