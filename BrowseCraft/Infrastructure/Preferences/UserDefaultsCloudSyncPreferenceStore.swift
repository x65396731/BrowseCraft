import Foundation

/// 中文注释：只保存用户对某个 Cloud account scope 的同步选择，不保存 CloudKit 原始账户标识。
final class UserDefaultsCloudSyncPreferenceStore: CloudSyncPreferenceStoring, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let keyPrefix: String

    init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "settings.cloudSyncEnabled"
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
    }

    func isCloudSyncEnabled(for scope: CloudAccountScope) -> Bool {
        guard scope.isCloud else {
            return false
        }
        return self.userDefaults.bool(forKey: self.key(for: scope))
    }

    func setCloudSyncEnabled(_ enabled: Bool, for scope: CloudAccountScope) {
        guard scope.isCloud else {
            return
        }
        self.userDefaults.set(enabled, forKey: self.key(for: scope))
    }

    private func key(for scope: CloudAccountScope) -> String {
        return "\(self.keyPrefix).\(scope.rawValue)"
    }
}
