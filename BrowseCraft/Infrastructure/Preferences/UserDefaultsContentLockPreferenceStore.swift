import Foundation

/// 中文注释：收藏与历史锁定开关的本机存储（`docs/design/Content-Lock-Design.md` 第 2.1 节），不随 iCloud 同步。
/// 中文注释：`@unchecked` 的依据（architecture.md 第 4 节）：成员全不可变；`UserDefaults` 自身线程安全。
final class UserDefaultsContentLockPreferenceStore: ContentLockPreferenceStoring, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "settings.contentLockEnabled"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func isContentLockEnabled() -> Bool {
        return self.userDefaults.bool(forKey: self.key)
    }

    func setContentLockEnabled(_ enabled: Bool) {
        self.userDefaults.set(enabled, forKey: self.key)
    }
}
