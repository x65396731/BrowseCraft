import Foundation

/// 中文注释：只保存用户对某个 Cloud account scope 的同步选择，不保存 CloudKit 原始账户标识。
final class UserDefaultsCloudSyncPreferenceStore: CloudSyncPreferenceStoring, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let keyPrefix: String
    private let consentKey: String

    init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "settings.cloudSyncEnabled",
        consentKey: String = "settings.cloudSyncUserConsent"
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
        self.consentKey = consentKey
    }

    func hasCloudSyncUserConsent() -> Bool {
        if self.userDefaults.object(forKey: self.consentKey) != nil {
            return self.userDefaults.bool(forKey: self.consentKey)
        }

        // 中文注释：升级兼容——旧版本只保存账号级开关；发现任一已开启账号时迁移为已主动授权。
        let hasLegacyEnabledAccount: Bool = self.userDefaults.dictionaryRepresentation()
            .contains { entry in
                entry.key.hasPrefix("\(self.keyPrefix).") && (entry.value as? Bool == true)
            }
        if hasLegacyEnabledAccount {
            self.userDefaults.set(true, forKey: self.consentKey)
        }
        return hasLegacyEnabledAccount
    }

    func setCloudSyncUserConsent(_ consented: Bool) {
        self.userDefaults.set(consented, forKey: self.consentKey)
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
