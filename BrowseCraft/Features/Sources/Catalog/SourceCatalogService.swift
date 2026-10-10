import BrowseCraftCore
import BrowseCraftDomain

struct SourceCatalogService: Sendable {
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

    func addSource(
        _ catalogSource: CatalogSource,
        origin: SourceOrigin? = nil
    ) async throws -> AddCatalogSourceResult {
        return try await self.addCatalogSourceUseCase.execute(catalogSource, origin: origin)
    }

    /// 目录跟随：先比指纹再物化（复审 B-4）。
    func ruleUpdates(in catalogSources: [CatalogSource], existingSources: [Source]) async throws -> CatalogRuleUpdatePlan {
        return try await self.addCatalogSourceUseCase.ruleUpdates(in: catalogSources, existingSources: existingSources)
    }

    func applyRuleUpdates(_ catalogSources: [CatalogSource], existingSources: [Source]) async throws -> AppliedCatalogRuleUpdates {
        return try await self.addCatalogSourceUseCase.applyRuleUpdates(catalogSources, existingSources: existingSources)
    }

    func stampCatalogRuleFingerprints(_ fingerprintsBySourceID: [String: String]) async throws {
        try await self.addCatalogSourceUseCase.stampCatalogRuleFingerprints(fingerprintsBySourceID)
    }
}
