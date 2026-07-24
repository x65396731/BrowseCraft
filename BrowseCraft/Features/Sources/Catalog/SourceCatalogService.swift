import BrowseCraftCore
import BrowseCraftAPIKit

struct SourceCatalogService {
    private let addCatalogSourceUseCase: AddCatalogSourceUseCase
    private let loadCatalogSourcesUseCase: LoadCatalogSourcesUseCase

    init(
        addCatalogSourceUseCase: AddCatalogSourceUseCase,
        loadCatalogSourcesUseCase: LoadCatalogSourcesUseCase
    ) {
        self.addCatalogSourceUseCase = addCatalogSourceUseCase
        self.loadCatalogSourcesUseCase = loadCatalogSourcesUseCase
    }

    func loadSources() async throws -> [BrowseCraftCatalogSource] {
        return try await self.loadCatalogSourcesUseCase.execute()
    }

    func addSource(_ catalogSource: BrowseCraftCatalogSource) async throws -> AddCatalogSourceResult {
        return try await self.addCatalogSourceUseCase.execute(catalogSource)
    }
}
