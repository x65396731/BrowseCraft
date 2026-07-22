import Foundation

protocol CloudSyncEngineStateStoring: Sendable {
    func loadState(for accountScope: CloudAccountScope) throws -> Data?
    func saveState(_ data: Data, for accountScope: CloudAccountScope) throws
    func clearState(for accountScope: CloudAccountScope) throws
}

protocol CloudRecordMetadataStoring: Sendable {
    func systemFields(
        accountScope: CloudAccountScope,
        recordName: String
    ) throws -> Data?
    func saveSystemFields(
        _ data: Data,
        accountScope: CloudAccountScope,
        recordName: String
    ) throws
}

enum CloudRecordZoneRecoveryStrategy: String, Hashable, Sendable {
    /// 中文注释：Zone 意外丢失或加密数据重置时，保留本地业务数据并重新上传。
    case rebuildFromLocalData
    /// 中文注释：用户从 iCloud 存储管理中清除数据时，同步清除本地云分区缓存。
    case purgeLocalCloudData
}

protocol CloudRecordZoneRecoveryStoring: Sendable {
    func recoverDeletedZone(
        for accountScope: CloudAccountScope,
        strategy: CloudRecordZoneRecoveryStrategy
    ) throws
}
