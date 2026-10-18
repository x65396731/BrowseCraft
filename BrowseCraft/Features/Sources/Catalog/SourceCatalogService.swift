import BrowseCraftCore
import BrowseCraftDomain

struct SourceCatalogService: Sendable {
    private let addCatalogSourceUseCase: AddCatalogSourceUseCase
    private let loadCatalogSourcesUseCase: LoadCatalogSourcesUseCase
    /// 中文注释：只有 DEBUG 演示模式（拍商城截图）传入，替代服务端目录；正式装配为 nil。
    private let catalogSourcesOverride: [CatalogSource]?

    init(
        addCatalogSourceUseCase: AddCatalogSourceUseCase,
        loadCatalogSourcesUseCase: LoadCatalogSourcesUseCase,
        catalogSourcesOverride: [CatalogSource]? = nil
    ) {
        self.addCatalogSourceUseCase = addCatalogSourceUseCase
        self.loadCatalogSourcesUseCase = loadCatalogSourcesUseCase
        self.catalogSourcesOverride = catalogSourcesOverride
    }

    func loadSources() async throws -> [CatalogSource] {
        if let catalogSourcesOverride: [CatalogSource] = self.catalogSourcesOverride {
            return catalogSourcesOverride
        }
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
