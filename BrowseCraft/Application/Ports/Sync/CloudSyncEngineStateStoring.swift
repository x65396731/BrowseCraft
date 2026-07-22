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
