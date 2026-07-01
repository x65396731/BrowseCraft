import Foundation

/// Loads all user-configured sources.
struct LoadSourcesUseCase {
    private let sourceRepository: SourceRepository

    init(sourceRepository: SourceRepository) {
        self.sourceRepository = sourceRepository
    }

    func execute() throws -> [Source] {
        return try self.sourceRepository.fetchSources()
    }
}

