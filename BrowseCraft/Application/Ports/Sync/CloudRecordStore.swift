import Foundation

// 中文注释：CloudRecordStore 抽象同步用例需要的云端记录能力；具体云服务由 Infrastructure 实现。
protocol CloudRecordStore {
    func fetchChangedSourceRecords(since token: Data?) throws -> SourceCloudChangeSet
    func saveSourceRecords(_ records: [SourceCloudPayload]) throws
    func fetchChangedFavoriteItemRecords(since token: Data?) throws -> FavoriteItemCloudChangeSet
    func saveFavoriteItemRecords(_ records: [FavoriteItemCloudPayload]) throws
}

struct SourceCloudChangeSet: Hashable {
    var records: [SourceCloudPayload]
    var changeToken: Data?
}

struct FavoriteItemCloudChangeSet: Hashable {
    var records: [FavoriteItemCloudPayload]
    var changeToken: Data?
}
