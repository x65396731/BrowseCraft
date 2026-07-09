import Foundation
import BrowseCraftCore
import BrowseCraftRulesKit

enum CatalogSourceImportError: LocalizedError {
    case invalidBaseURL(String)
    case invalidFeedURL(String)
    case invalidEntryURL(String)
    case invalidRuleJSON
    case unsupportedRuleValue(field: String, value: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let urlString):
            return "Invalid source base URL: \(urlString)."
        case .invalidFeedURL(let urlString):
            return "Invalid RSS feed URL: \(urlString)."
        case .invalidEntryURL(let urlString):
            return "Invalid video entry URL: \(urlString)."
        case .invalidRuleJSON:
            return "Invalid website rule JSON."
        case .unsupportedRuleValue(let field, let value):
            return "Unsupported catalog rule value \(field)=\(value)."
        }
    }
}

struct AddCatalogSourceResult {
    let source: Source
    let listOutput: SourceListOutput?
}

struct LoadCatalogSourcesUseCase {
    private let pageDataLoader: PageDataLoader
    private let catalogAPIURL: URL

    init(
        pageDataLoader: PageDataLoader,
        catalogAPIURL: URL = URL(string: "https://anyportal.online/catalog/sources")!
    ) {
        self.pageDataLoader = pageDataLoader
        self.catalogAPIURL = catalogAPIURL
    }

    func execute() async throws -> [BrowseCraftCatalogSource] {
        let data: Data = try await self.pageDataLoader.getData(
            from: self.catalogAPIURL,
            request: self.requestConfig
        )
        return try BrowseCraftSourceCatalog.sources(from: data)
    }

    private var requestConfig: RequestConfig {
        return RequestConfig(
            headers: [
                "Accept": "application/json"
            ]
        )
    }
}

// 中文注释：Catalog 来源必须先通过既存 runtime 加载流程，加载成功后才写入本地 DB。
struct AddCatalogSourceUseCase {
    private let sourceRepository: SourceRepository
    private let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase
    private let videoTabDiscoveryUseCase: VideoSourceTabDiscoveryUseCase?
    private let validateSourceListLoadUseCase: ValidateSourceListLoadUseCase
    private let catalogSourceMaterializer: CatalogSourceMaterializer
    private let now: () -> Date

    init(
        sourceRepository: SourceRepository,
        refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase,
        videoTabDiscoveryUseCase: VideoSourceTabDiscoveryUseCase? = nil,
        validateSourceListLoadUseCase: ValidateSourceListLoadUseCase = ValidateSourceListLoadUseCase(),
        catalogSourceMaterializer: CatalogSourceMaterializer = CatalogSourceMaterializer(),
        now: @escaping () -> Date = Date.init
    ) {
        self.sourceRepository = sourceRepository
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
        self.videoTabDiscoveryUseCase = videoTabDiscoveryUseCase
        self.validateSourceListLoadUseCase = validateSourceListLoadUseCase
        self.catalogSourceMaterializer = catalogSourceMaterializer
        self.now = now
    }

    func execute(_ catalogSource: BrowseCraftCatalogSource) async throws -> AddCatalogSourceResult {
        if let existingSource: Source = try self.sourceRepository.fetchSources().first(where: { source in
            return source.id == catalogSource.id
        }) {
            let currentCatalogSource: Source = try self.catalogSourceMaterializer.source(
                from: catalogSource,
                createdAt: existingSource.createdAt,
                updatedAt: self.now(),
                enabled: existingSource.enabled
            )
            let discoveredSource: Source = try await self.sourceWithDiscoveredVideoTabs(currentCatalogSource)
            if discoveredSource != existingSource {
                try self.sourceRepository.saveSource(discoveredSource)
            }

            return AddCatalogSourceResult(source: discoveredSource, listOutput: nil)
        }

        let createdAt: Date = self.now()
        let source: Source = try await self.sourceWithDiscoveredVideoTabs(
            try self.catalogSourceMaterializer.source(
                from: catalogSource,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        )
        let listOutput: SourceListOutput = try await self.refreshSourceRuntimeUseCase.execute(
            source: source,
            listContext: nil
        )
        try self.validateSourceListLoadUseCase.execute(listOutput)
        try self.sourceRepository.saveSource(source)
        return AddCatalogSourceResult(source: source, listOutput: listOutput)
    }

    private func sourceWithDiscoveredVideoTabs(_ source: Source) async throws -> Source {
        guard let videoTabDiscoveryUseCase: VideoSourceTabDiscoveryUseCase,
              case .video(let configuration) = source.configuration else {
            return source
        }

        var discoveredSource: Source = source
        let tabs: [VideoSourceListTab] = try await videoTabDiscoveryUseCase.discoverTabs(
            sourceID: source.id,
            definition: configuration.definition,
            explicitTabs: configuration.listTabs
        )
        discoveredSource.configuration = .video(
            VideoSourceConfiguration(
                definition: configuration.definition,
                listTabs: tabs
            )
        )
        return discoveredSource
    }
}
