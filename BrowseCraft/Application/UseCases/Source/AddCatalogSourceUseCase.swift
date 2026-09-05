import Foundation
import BrowseCraftCore
import BrowseCraftDomain

enum CatalogSourceImportError: LocalizedError {
    case invalidBaseURL(String)
    case invalidFeedURL(String)
    case invalidEntryURL(String)
    case invalidRuleJSON(sourceID: String, name: String, kind: String, reason: String)
    case unsupportedRuleValue(field: String, value: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let urlString):
            return String(format: NSLocalizedString("catalog_import_error_invalid_base_url", comment: ""), urlString)
        case .invalidFeedURL(let urlString):
            return String(format: NSLocalizedString("catalog_import_error_invalid_feed_url", comment: ""), urlString)
        case .invalidEntryURL(let urlString):
            return String(format: NSLocalizedString("catalog_import_error_invalid_entry_url", comment: ""), urlString)
        case .invalidRuleJSON(_, let name, _, let reason):
            return String(format: NSLocalizedString("catalog_import_error_invalid_rule_json", comment: ""), name, reason)
        case .unsupportedRuleValue(let field, let value):
            return String(format: NSLocalizedString("catalog_import_error_unsupported_value", comment: ""), field, value)
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
    private let requestHeaders: @Sendable () -> [String: String]
    private let catalogRuleDecryptor: CatalogRuleDecryptor
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    init(
        pageDataLoader: PageDataLoader,
        catalogAPIURL: URL? = URL(string: "https://anyportal.online/catalog/sources"),
        requestHeaders: @escaping @Sendable () -> [String: String] = { [:] },
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

    func execute() async throws -> [CatalogSource] {
        guard let catalogAPIURL: URL = self.catalogAPIURL else {
            throw CatalogSourceImportError.invalidBaseURL("catalog-api")
        }

        let requestConfig: RequestConfig = self.requestConfig
        #if DEBUG
        let headers: [String: String] = requestConfig.headers ?? [:]
        AppDebugLog.write(
            "[BrowseCraftCatalog] request " +
            "url=\(catalogAPIURL.absoluteString) " +
            "headerCount=\(headers.count) " +
            "hasRequiredPortalHeaders=\(self.hasRequiredPortalHeaders(headers))"
        )
        #endif

        let data: Data = try await self.pageDataLoader.loadData(
            PageLoadRequest(
                url: catalogAPIURL,
                requestConfig: requestConfig,
                sourceContext: nil,
                cachePolicy: .reloadIgnoringLocalCacheData
            )
        ).data
        return try CatalogSourcePayloadDecoder().decode(
            from: self.catalogSourceData(from: data)
        )
    }

    private var requestConfig: RequestConfig {
        return RequestConfig(
            headers: SourceAPIRequestHeaders.catalogHeaders(base: self.requestHeaders())
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
        AppDebugLog.write(
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

private struct CatalogSourcePayloadDecoder {
    func decode(from data: Data) throws -> [CatalogSource] {
        return try JSONDecoder().decode([CatalogSourcePayload].self, from: data).map { payload in
            return CatalogSource(
                id: payload.id,
                name: payload.name,
                baseURL: payload.baseURL,
                kind: payload.kind,
                ruleJSON: payload.ruleJSON.jsonString
            )
        }
    }
}

private struct CatalogSourcePayload: Decodable {
    let id: String
    let name: String
    let baseURL: String
    let kind: CatalogSourceKind
    let ruleJSON: CatalogSourceJSONValue

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case baseURL
        case kind
        case ruleJSON
        case payload
    }

    private enum PayloadCodingKeys: String, CodingKey {
        case ruleJSON
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.baseURL = try container.decode(String.self, forKey: .baseURL)
        self.kind = try container.decode(CatalogSourceKind.self, forKey: .kind)

        if container.contains(.payload) {
            let payloadDecoder: Decoder = try container.superDecoder(forKey: .payload)
            let payloadContainer: KeyedDecodingContainer<PayloadCodingKeys> =
                try payloadDecoder.container(keyedBy: PayloadCodingKeys.self)
            self.ruleJSON = try payloadContainer.decode(
                CatalogSourceJSONValue.self,
                forKey: .ruleJSON
            )
            return
        }

        let outerRuleJSON: CatalogSourceJSONValue = try container.decode(
            CatalogSourceJSONValue.self,
            forKey: .ruleJSON
        )
        if case .object(let object) = outerRuleJSON,
           let nestedRuleJSON: CatalogSourceJSONValue = object["ruleJSON"] {
            self.ruleJSON = nestedRuleJSON
        } else {
            self.ruleJSON = outerRuleJSON
        }
    }
}

private enum CatalogSourceJSONValue: Codable {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case object([String: CatalogSourceJSONValue])
    case array([CatalogSourceJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container: SingleValueDecodingContainer = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value: Bool = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value: Int = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value: Double = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value: String = try? container.decode(String.self) {
            self = .string(value)
        } else if let value: [String: CatalogSourceJSONValue] = try? container.decode(
            [String: CatalogSourceJSONValue].self
        ) {
            self = .object(value)
        } else if let value: [CatalogSourceJSONValue] = try? container.decode(
            [CatalogSourceJSONValue].self
        ) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported catalog rule JSON value."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container: SingleValueEncodingContainer = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var jsonString: String {
        let data: Data = (try? JSONEncoder().encode(self)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
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
struct AddCatalogSourceUseCase: Sendable {
    private let sourceRepository: SourceRepository
    private let refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase
    private let validateSourceListLoadUseCase: ValidateSourceListLoadUseCase
    private let catalogSourceMaterializer: CatalogSourceMaterializer
    private let now: @Sendable () -> Date

    init(
        sourceRepository: SourceRepository,
        refreshSourceRuntimeUseCase: RefreshSourceRuntimeUseCase,
        validateSourceListLoadUseCase: ValidateSourceListLoadUseCase = ValidateSourceListLoadUseCase(),
        catalogSourceMaterializer: CatalogSourceMaterializer = CatalogSourceMaterializer(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sourceRepository = sourceRepository
        self.refreshSourceRuntimeUseCase = refreshSourceRuntimeUseCase
        self.validateSourceListLoadUseCase = validateSourceListLoadUseCase
        self.catalogSourceMaterializer = catalogSourceMaterializer
        self.now = now
    }

    /// - Parameter origin: 来源出身；从「我的生成」添加时传 `.personalGeneration`，本地副本才会随服务器裁决清理。
    func execute(
        _ catalogSource: CatalogSource,
        origin: SourceOrigin? = nil
    ) async throws -> AddCatalogSourceResult {
        if let existingSource: Source = try self.sourceRepository.fetchSources().first(where: { source in
            return source.id == catalogSource.id
        }) {
            let currentCatalogSource: Source = try self.catalogSourceMaterializer.source(
                from: catalogSource,
                createdAt: existingSource.createdAt,
                updatedAt: self.now(),
                enabled: existingSource.enabled,
                origin: origin ?? existingSource.origin
            )
            if currentCatalogSource != existingSource {
                try self.sourceRepository.saveSource(currentCatalogSource)
            }

            return AddCatalogSourceResult(source: currentCatalogSource, listOutput: nil)
        }

        let createdAt: Date = self.now()
        let source: Source = try self.catalogSourceMaterializer.source(
            from: catalogSource,
            createdAt: createdAt,
            updatedAt: createdAt,
            origin: origin
        )
        // Catalog 导入只验证默认入口。其它 tab 由 Library 按当前 tab 独立加载并记录失败状态。
        let defaultListContext: ListContext? = nil
        let listOutput: SourceListOutput = try await self.refreshSourceRuntimeUseCase.execute(
            source: source,
            listContext: ListContextTransfer(value: defaultListContext)
        )
        try self.validateSourceListLoadUseCase.execute(listOutput)
        try self.sourceRepository.saveSource(source)
        return AddCatalogSourceResult(source: source, listOutput: listOutput)
    }
}
