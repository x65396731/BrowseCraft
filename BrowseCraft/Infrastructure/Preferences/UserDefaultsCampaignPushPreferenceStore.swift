import Foundation

/// 中文注释：「活动推送」开关（Campaign-And-Rate-Notices-Design.md 第四节）存在本机，默认关，不随账号切换清掉。
/// 中文注释：`@unchecked` 的依据（architecture.md 第 4 节）：成员全不可变；`UserDefaults` 自身线程安全。
final class UserDefaultsCampaignPushPreferenceStore: CampaignPushPreferenceStoring, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "settings.campaignPushEnabled"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func isCampaignPushEnabled() -> Bool {
        return self.userDefaults.bool(forKey: self.key)
    }

    func setCampaignPushEnabled(_ enabled: Bool) {
        self.userDefaults.set(enabled, forKey: self.key)
    }
}
