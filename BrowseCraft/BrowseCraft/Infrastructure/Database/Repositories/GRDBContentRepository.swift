import Foundation
import GRDB

final class GRDBContentRepository: ContentRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func fetchItems() throws -> [ContentItem] {
        return try self.fetchItems(sourceId: nil)
    }

    func fetchItems(sourceId: String?) throws -> [ContentItem] {
        return try self.database.queue.read { database in
            let records: [ContentItemRecord]

            if let sourceId: String = sourceId {
                records = try ContentItemRecord
                    .filter(Column("sourceId") == sourceId)
                    .order(Column("updatedAt").desc)
                    .fetchAll(database)
            } else {
                records = try ContentItemRecord
                    .order(Column("updatedAt").desc)
                    .fetchAll(database)
            }

            return records.map { record in
                return record.domainModel()
            }
        }
    }

    func saveItems(_ items: [ContentItem]) throws {
        try self.database.queue.write { database in
            for item: ContentItem in items {
                var record: ContentItemRecord = ContentItemRecord(item: item)
                try record.save(database)
            }
        }
    }
}

