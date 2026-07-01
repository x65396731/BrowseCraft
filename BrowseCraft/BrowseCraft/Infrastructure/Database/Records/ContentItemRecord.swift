import Foundation
import GRDB

struct ContentItemRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "contentItems"

    var id: String
    var sourceId: String
    var title: String
    var detailURL: String
    var coverURL: String?
    var type: String
    var latestText: String?
    var updatedAt: Date?

    init(item: ContentItem) {
        self.id = item.id
        self.sourceId = item.sourceId
        self.title = item.title
        self.detailURL = item.detailURL
        self.coverURL = item.coverURL
        self.type = item.type.rawValue
        self.latestText = item.latestText
        self.updatedAt = item.updatedAt
    }

    func domainModel() -> ContentItem {
        return ContentItem(
            id: self.id,
            sourceId: self.sourceId,
            title: self.title,
            detailURL: self.detailURL,
            coverURL: self.coverURL,
            type: ContentType(rawValue: self.type) ?? .article,
            latestText: self.latestText,
            updatedAt: self.updatedAt
        )
    }
}

