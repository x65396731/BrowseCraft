import Foundation

/// 中文注释：Cloud Sync 开关按 Cloud account scope 保存，local.default 永远不启用同步。
protocol CloudSyncPreferenceStoring: Sendable {
    func isCloudSyncEnabled(for scope: CloudAccountScope) -> Bool
    func setCloudSyncEnabled(_ enabled: Bool, for scope: CloudAccountScope)
}
