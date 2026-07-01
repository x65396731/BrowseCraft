import Foundation

/// Domain-facing storage API for parsed content items.
protocol ContentRepository {
    func fetchItems() throws -> [ContentItem]
    func fetchItems(sourceId: String?) throws -> [ContentItem]
    func saveItems(_ items: [ContentItem]) throws
}

