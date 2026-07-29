import BrowseCraftCore
import BrowseCraftDomain

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

    func loadSources() async throws -> [CatalogSource] {
        return try await self.loadCatalogSourcesUseCase.execute()
    }

    func addSource(_ catalogSource: CatalogSource) async throws -> AddCatalogSourceResult {
        return try await self.addCatalogSourceUseCase.execute(catalogSource)
    }
}
