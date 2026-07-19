import Foundation
import BrowseCraftCore
import BrowseCraftRulesKit

enum CatalogSourceImportError: LocalizedError {
    case invalidBaseURL(String)
    case invalidFeedURL(String)
    case invalidEntryURL(String)
    case invalidRuleJSON(sourceID: String, name: String, kind: String, reason: String)
    case unsupportedRuleValue(field: String, value: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let urlString):
            return "Invalid source base URL: \(urlString)."
        case .invalidFeedURL(let urlString):
            return "Invalid RSS feed URL: \(urlString)."
        case .invalidEntryURL(let urlString):
            return "Invalid video entry URL: \(urlString)."
        case .invalidRuleJSON(let sourceID, let name, let kind, let reason):
            return "Invalid catalog rule JSON: source=\(sourceID) name=\(name) kind=\(kind) reason=\(reason)"
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
    private let catalogAPIURL: URL?
    private let requestHeaders: () -> [String: String]
    private let catalogRuleDecryptor: CatalogRuleDecryptor
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    init(
        pageDataLoader: PageDataLoader,
        catalogAPIURL: URL? = URL(string: "https://anyportal.online/catalog/sources"),
        requestHeaders: @escaping () -> [String: String] = { [:] },
        catalogRuleDecryptor: CatalogRuleDecryptor = CatalogRuleDecryptor(),
        jsonDecoder: JSONDecoder = JSONDecoder(),
        jsonEncoder: JSONEncoder = JSONEncoder()
    ) {
        self.pageDataLoader = pageDataLoader
        self.catalogAPIURL = catalogAPIURL
        self.requestHeaders = requestHeaders
        self.catalogRuleDecryptor = catalogRuleDecryptor
        self.jsonDecoder = jsonDecoder
        self.jsonEncoder = jsonEncoder
    }

    func execute() async throws -> [BrowseCraftCatalogSource] {
        guard let catalogAPIURL: URL = self.catalogAPIURL else {
            throw CatalogSourceImportError.invalidBaseURL("catalog-api")
        }

        let requestConfig: RequestConfig = self.requestConfig
        #if DEBUG
        let headers: [String: String] = requestConfig.headers ?? [:]
        print(
            "[BrowseCraftCatalog] request " +
            "url=\(catalogAPIURL.absoluteString) " +
            "headerCount=\(headers.count) " +
            "hasRequiredPortalHeaders=\(self.hasRequiredPortalHeaders(headers))"
        )
        #endif

        let data: Data = try await self.pageDataLoader.getData(
            from: catalogAPIURL,
            request: requestConfig
        )
        return try BrowseCraftSourceCatalog.sources(from: self.catalogSourceData(from: data))
    }

    private var requestConfig: RequestConfig {
        return RequestConfig(
            headers: APIRequestHeaders.catalogHeaders(base: self.requestHeaders())
        )
    }

    private func catalogSourceData(from data: Data) throws -> Data {
        let encryptedSources: [EncryptedCatalogSourcePayload] = try self.jsonDecoder.decode(
            [EncryptedCatalogSourcePayload].self,
            from: data
        )

        let encryptedRuleCount: Int = encryptedSources.filter { source in
            source.encryptedRule != nil
        }.count

        #if DEBUG
        print(
            "[BrowseCraftCatalog] payload " +
            "sources=\(encryptedSources.count) " +
            "encryptedRules=\(encryptedRuleCount)"
        )
        #endif

        guard encryptedRuleCount > 0 else {
            return data
        }

        let plainSources: [PlainCatalogSourcePayload] = try encryptedSources.map { source in
            guard let encryptedRule: EncryptedCatalogRule = source.encryptedRule else {
                throw CatalogRuleDecryptionError.invalidPlaintext
            }

            let decryptedRule: CatalogRuleJSONValue = try self.catalogRuleDecryptor.decrypt(encryptedRule)
            return PlainCatalogSourcePayload(
                id: source.id,
                name: source.name,
                baseURL: source.baseURL,
                kind: source.kind,
                ruleJSON: decryptedRule.importRuleJSON
            )
        }

        return try self.jsonEncoder.encode(plainSources)
    }

    private func hasRequiredPortalHeaders(_ headers: [String: String]) -> Bool {
        let requiredHeaders: [String] = [
            "userId",
            "osInfo",
            "deviceInfo",
            "aplVersion",
            "X-Request-Id"
        ]
        let headerNames: Set<String> = Set(headers.keys.map { $0.lowercased() })
        return requiredHeaders.allSatisfy { headerName in
            headerNames.contains(headerName.lowercased())
        }
    }
}

private struct EncryptedCatalogSourcePayload: Decodable {
    let id: String
    let name: String
    let baseURL: String
    let kind: String
    let encryptedRule: EncryptedCatalogRule?
}

private struct PlainCatalogSourcePayload: Encodable {
    let id: String
    let name: String
    let baseURL: String
    let kind: String
    let ruleJSON: CatalogRuleJSONValue
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
        // Catalog 导入只验证默认入口。其它 tab 由 Library 按当前 tab 独立加载并记录失败状态。
        let defaultListContext: ListContext? = nil
        let listOutput: SourceListOutput = try await self.refreshSourceRuntimeUseCase.execute(
            source: source,
            listContext: defaultListContext
        )
        try self.validateSourceListLoadUseCase.execute(listOutput)
        try self.sourceRepository.saveSource(source)
        return AddCatalogSourceResult(source: source, listOutput: listOutput)
    }

    private func sourceWithDiscoveredVideoTabs(_ source: Source) async throws -> Source {
        guard let videoTabDiscoveryUseCase: VideoSourceTabDiscoveryUseCase,
              case .video(.legacyPreset(let legacyConfiguration)) = source.configuration else {
            return source
        }

        var discoveredSource: Source = source
        let tabs: [VideoSourceListTab] = try await videoTabDiscoveryUseCase.discoverTabs(
            sourceID: source.id,
            definition: legacyConfiguration.definition,
            explicitTabs: legacyConfiguration.listTabs
        )
        discoveredSource.configuration = .video(
            VideoSourceConfiguration(
                definition: legacyConfiguration.definition,
                listTabs: tabs
            )
        )
        return discoveredSource
    }
}
