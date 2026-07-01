import Foundation

/// Loads content items for Library.
struct LoadLibraryUseCase {
    private let contentRepository: ContentRepository

    init(contentRepository: ContentRepository) {
        self.contentRepository = contentRepository
    }

    func execute(sourceId: String? = nil) throws -> [ContentItem] {
        return try self.contentRepository.fetchItems(sourceId: sourceId)
    }
}

