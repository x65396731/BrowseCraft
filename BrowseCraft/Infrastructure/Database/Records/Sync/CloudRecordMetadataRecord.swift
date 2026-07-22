import Foundation
import GRDB

struct CloudRecordMetadataRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "cloud_record_metadata"

    var accountScope: String
    var recordName: String
    var systemFields: Data
    var updatedAt: Date
}
