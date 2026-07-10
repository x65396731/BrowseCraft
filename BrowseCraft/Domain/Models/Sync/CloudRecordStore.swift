import Foundation

// 中文注释：CloudRecordStore 抽象云端记录存储；P6-iCloud-1 只用 mock，P6-iCloud-2 再接 CloudKit。
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

struct SourceCloudRecord: Hashable {
    var payload: SourceCloudPayload
    var serverUpdatedAt: Date
    var version: Int
}

struct FavoriteItemCloudChangeSet: Hashable {
    var records: [FavoriteItemCloudPayload]
    var changeToken: Data?
}

struct FavoriteItemCloudRecord: Hashable {
    var payload: FavoriteItemCloudPayload
    var serverUpdatedAt: Date
    var version: Int
}
