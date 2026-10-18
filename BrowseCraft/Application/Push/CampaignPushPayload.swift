import Foundation

/// 锁屏活动推送负载的识别（docs/design/Campaign-And-Rate-Notices-Design.md 第六节）。
///
/// 中文注释：服务器上的活动脚本经现有 APNs 通道发送，负载带 `kind` 为 campaign；标题与正文由服务端按设备登记的语言取好，
/// App 不读。点开时只刷新 coin 余额、不跳页——coin 在推送发出前已由服务端入账，推送只告知（`BCA-SYNC-012`）。
enum CampaignPushPayload {
    static let kindKey: String = "kind"
    static let campaignKind: String = "campaign"

    /// 中文注释：在系统回调所在的 nonisolated 上下文里判定，结果是 Sendable 的 Bool，可安全切主线程。
    static func isCampaign(_ userInfo: [AnyHashable: Any]) -> Bool {
        return (userInfo[Self.kindKey] as? String) == Self.campaignKind
    }
}
