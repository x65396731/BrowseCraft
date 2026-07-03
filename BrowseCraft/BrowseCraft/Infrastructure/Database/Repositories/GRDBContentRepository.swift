import Foundation
import GRDB

// 中文注释：GRDBContentRepository.swift 属于数据库仓储实现层，用于说明本文件承载的核心职责。

/// 中文注释：GRDBContentRepository 是 final class，负责本模块中的对应职责。
final class GRDBContentRepository: ContentRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    /// 中文注释：fetchItems 方法封装当前类型的一段业务或界面行为。
    func fetchItems() throws -> [ContentItem] {
        return try self.fetchItems(sourceId: nil)
    }

    /// 中文注释：fetchItems 方法封装当前类型的一段业务或界面行为。
    func fetchItems(sourceId: String?) throws -> [ContentItem] {
        return try self.fetchItems(sourceId: sourceId, context: nil)
    }

    func fetchItems(sourceId: String?, context: ListContext?) throws -> [ContentItem] {
        return try self.database.queue.read { database in
            let records: [ContentItemRecord]
            var request: QueryInterfaceRequest<ContentItemRecord> = ContentItemRecord.all()

            if let sourceId: String = sourceId {
                request = request.filter(Column("sourceId") == sourceId)
            }

            request = self.request(request, filteredBy: context)
            records = try request
                .order(Column("updatedAt").desc)
                .fetchAll(database)

            return records.map { record in
                return record.domainModel()
            }
        }
    }

    /// 中文注释：saveItems 方法封装当前类型的一段业务或界面行为。
    func saveItems(_ items: [ContentItem]) throws {
        try self.database.queue.write { database in
            for item: ContentItem in items {
                var record: ContentItemRecord = ContentItemRecord(item: item)
                try record.save(database)
            }
        }
    }

    func replaceItems(_ items: [ContentItem], sourceId: String, context: ListContext?) throws {
        try self.database.queue.write { database in
            // 中文注释：刷新列表代表该 source/tab/listRule 的缓存边界重置，先删旧记录再写新记录。
            var request: QueryInterfaceRequest<ContentItemRecord> = ContentItemRecord
                .filter(Column("sourceId") == sourceId)
            request = self.request(request, filteredBy: context)
            try request.deleteAll(database)

            for item: ContentItem in items {
                var record: ContentItemRecord = ContentItemRecord(item: item)
                try record.save(database)
            }
        }
    }

    private func request(
        _ request: QueryInterfaceRequest<ContentItemRecord>,
        filteredBy context: ListContext?
    ) -> QueryInterfaceRequest<ContentItemRecord> {
        var scopedRequest: QueryInterfaceRequest<ContentItemRecord> = request

        if let tabId: String = context?.tabId {
            scopedRequest = scopedRequest.filter(Column("contextTabId") == tabId)
        }

        if let listRuleId: String = context?.listRuleId {
            scopedRequest = scopedRequest.filter(Column("contextListRuleId") == listRuleId)
        }

        return scopedRequest
    }
}
