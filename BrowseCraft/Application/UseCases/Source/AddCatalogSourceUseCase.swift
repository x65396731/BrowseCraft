import CryptoKit
import Foundation
import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftLog

enum CatalogSourceImportError: LocalizedError {
    case invalidBaseURL(String)
    case invalidEntryURL(String)
    case invalidRuleJSON(sourceID: String, name: String, kind: String, reason: String)
    case unsupportedRuleValue(field: String, value: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let urlString):
            return String(format: NSLocalizedString("catalog_import_error_invalid_base_url", comment: ""), urlString)
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

/// 目录跟随的比较结果（复审 B-4）：要覆盖的条目，以及规则相等但本地还没记指纹的来源（只盖指纹）。
struct CatalogRuleUpdatePlan: Sendable {
    let updates: [CatalogSource]
    let unchangedFingerprintsBySourceID: [String: String]
}

/// 一批目录覆盖的结果：一个写事务里写入的来源，以及物化失败、保留旧规则的条目（按来源 id 记错误）。
struct AppliedCatalogRuleUpdates: Sendable {
    let sources: [Source]
    let failuresBySourceID: [String: String]
}

struct LoadCatalogSourcesUseCase {
    private let pageDataLoader: PageDataLoader
    private let catalogAPIURL: URL?
    private let requestHeaders: @Sendable () -> [String: String]
    private let catalogRuleDecryptor: CatalogRuleDecryptor
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    /// 中文注释：本版本认得的目录 kind；请求时显式带 `kinds=`（PortalCore §14.6：缺省只回 video / comic，book 要声明；RSS 已于 2026-09-16 下线）。
    /// 用 switch 穷举 CatalogSourceKind，新增 case 时编译期报缺，不会漏声明。
    static let requestedKinds: [CatalogSourceKind] = [.comic, .video, .book].filter { kind in
        switch kind {
        case .comic, .video, .book:
            return true
        }
    }

    /// 中文注释：`BCA-RUNTIME-006`——本版本认得的规则能力；服务端把需要未声明能力的来源过滤掉（与 `kinds` 同一机制）。
    /// `startPage`：0 起页码（`BC-LIST-124`），旧版不声明就拿不到这类来源，不会静默错一页。
    static let requestedFeatures: [String] = ["startPage"]

    static let defaultCatalogAPIURL: URL? = URL(
        string: "https://anyportal.online/catalog/sources?kinds=" + Self.requestedKinds.map(\.rawValue).joined(separator: ",")
            + "&features=" + Self.requestedFeatures.joined(separator: ",")
    )

    init(
        pageDataLoader: PageDataLoader,
        catalogAPIURL: URL? = LoadCatalogSourcesUseCase.defaultCatalogAPIURL,
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
        AppLog.debug(.rule, "catalog-request", [
            "url": .text("\(catalogAPIURL.absoluteString)"),
            "headerCount": .text("\(headers.count)"),
            "hasRequiredPortalHeaders": .text("\(self.hasRequiredPortalHeaders(headers))")
        ])
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
        AppLog.debug(.rule, "catalog-payload", [
            "sources": .text("\(encryptedSources.count)"),
            "encryptedRules": .text("\(encryptedRuleCount)")
        ])
        #endif

        guard encryptedRuleCount > 0 else {
            return data
        }

        // 中文注释：`BCA-RUNTIME-004`——单条解不开（没带密文、密钥不认得、解密或解码失败）逐条跳过并记 notice，
        // 与未知 kind 同一个纪律，不让一条坏条目拖垮整个目录；全部都解不开才整表失败（多半是密钥问题，该让用户看到错误而不是空目录）。
        var plainSources: [PlainCatalogSourcePayload] = []
        var firstFailure: (any Error)?
        for source: EncryptedCatalogSourcePayload in encryptedSources {
            do {
                guard let encryptedRule: EncryptedCatalogRule = source.encryptedRule else {
                    throw CatalogRuleDecryptionError.invalidPlaintext
                }
                let decryptedRule: CatalogRuleJSONValue = try self.catalogRuleDecryptor.decrypt(encryptedRule)
                plainSources.append(
                    PlainCatalogSourcePayload(
                        id: source.id,
                        name: source.name,
                        baseURL: source.baseURL,
                        kind: source.kind,
                        ruleJSON: decryptedRule.importRuleJSON,
                        section: source.section,
                        catalogSHA256: source.catalogSHA256
                    )
                )
            } catch {
                firstFailure = firstFailure ?? error
                AppLog.notice(.app, "catalog-skipped-undecryptable-rule", ["id": .id(source.id), "kind": .code(source.kind), "error": .error(error)])
            }
        }

        if plainSources.isEmpty, let failure: any Error = firstFailure {
            throw failure
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
    /// 中文注释：kind 逐条判定，本版本不认得的条目跳过并记日志，不让一条新 kind 拖垮整个目录（2026-09-14 核对的旧版整表失效问题）。
    func decode(from data: Data) throws -> [CatalogSource] {
        return try JSONDecoder().decode([CatalogSourcePayload].self, from: data).compactMap { payload in
            guard let kind: CatalogSourceKind = CatalogSourceKind(rawValue: payload.kind) else {
                // 中文注释：notice 级——Release 的日志也留得下，条款要求「记下被跳过的 id 与 kind」在线上才成立。
                AppLog.notice(.app, "catalog-skipped-unknown-kind", ["id": .id(payload.id), "kind": .code(payload.kind)])
                return nil
            }
            return CatalogSource(
                id: payload.id,
                name: payload.name,
                baseURL: payload.baseURL,
                kind: kind,
                ruleJSON: payload.ruleJSON.jsonString,
                section: payload.section.flatMap(CatalogSourceSection.init(rawValue:)),
                catalogRevision: payload.catalogSHA256
            )
        }
    }
}

private struct CatalogSourcePayload: Decodable {
    let id: String
    let name: String
    let baseURL: String
    let kind: String
    let ruleJSON: CatalogSourceJSONValue
    /// 明文分区（不在密文里）；类型不对时当作没有，不让一条坏字段拖垮整条。
    let section: String?
    /// 明文的服务端规则指纹（`BCA-OBS-022`）；缺失或类型不对时为 nil。
    let catalogSHA256: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case baseURL
        case kind
        case ruleJSON
        case payload
        case section
        case catalogSHA256
    }

    private enum PayloadCodingKeys: String, CodingKey {
        case ruleJSON
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.baseURL = try container.decode(String.self, forKey: .baseURL)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.section = (try? container.decodeIfPresent(String.self, forKey: .section)) ?? nil
        self.catalogSHA256 = (try? container.decodeIfPresent(String.self, forKey: .catalogSHA256)) ?? nil // try?: 类型不对当作没有，规则版本缺了只影响问题报告对版本

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
    let section: String?
    let catalogSHA256: String?
}

private struct PlainCatalogSourcePayload: Encodable {
    let id: String
    let name: String
    let baseURL: String
    let kind: String
    let ruleJSON: CatalogRuleJSONValue
    let section: String?
    let catalogSHA256: String?
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

    /// 目录条目规则原文（`ruleJSON`）的 SHA-256，记在来源行上作为「上次应用的目录规则」指纹。
    static func ruleFingerprint(of catalogSource: CatalogSource) -> String {
        let digest: SHA256.Digest = SHA256.hash(data: Data(catalogSource.ruleJSON.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 中文注释：目录跟随的判据（复审 B-4）：先比指纹，相同的条目不再物化；指纹不同或没记过的才物化并比较
    /// 名称、站点地址与整棵 `configuration`。相等的记下指纹（调用方盖上去），下次就不用再物化；物化失败按无更新处理。
    /// 非隔离的 async 方法，调用方 `await` 时离开主线程。
    func ruleUpdates(
        in catalogSources: [CatalogSource],
        existingSources: [Source]
    ) async throws -> CatalogRuleUpdatePlan {
        let existingByID: [String: Source] = Dictionary(existingSources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let knownFingerprints: [String: String] = try self.sourceRepository.catalogRuleFingerprints()
        var updates: [CatalogSource] = []
        var unchanged: [String: String] = [:]
        var revisions: [String: String] = [:]
        // 中文注释：每次跟随都给已添加来源记上服务端规则指纹（`BCA-OBS-022`），包括下面「指纹相同、不物化」的条目，
        // 存量来源刷新一次目录就补齐。
        defer {
            self.stampCatalogRevisions(revisions)
        }
        for catalogSource: CatalogSource in catalogSources {
            guard let existing: Source = existingByID[catalogSource.id] else {
                continue
            }
            if let revision: String = catalogSource.catalogRevision {
                revisions[catalogSource.id] = revision
            }
            let fingerprint: String = Self.ruleFingerprint(of: catalogSource)
            if knownFingerprints[catalogSource.id] == fingerprint {
                continue
            }
            guard let candidate: Source = try? self.catalogSourceMaterializer.source(
                from: catalogSource,
                createdAt: existing.createdAt,
                updatedAt: existing.updatedAt,
                enabled: existing.enabled,
                origin: existing.origin
            ) else {
                continue
            }
            if candidate.name != existing.name
                || candidate.baseURL != existing.baseURL
                || candidate.configuration != existing.configuration {
                updates.append(catalogSource)
            } else {
                unchanged[catalogSource.id] = fingerprint
            }
        }
        return CatalogRuleUpdatePlan(updates: updates, unchangedFingerprintsBySourceID: unchanged)
    }

    /// 中文注释：一批已添加来源的覆盖：按本地的 `createdAt / enabled / origin` 物化、`updatedAt` 取当前时间，
    /// 全部在一个写事务里写入并盖上指纹（复审 B-4：之前每条各一个事务、各重读一次来源表）。
    /// 物化失败的条目保留旧规则，按 id 交回错误；不重新验证列表，与同 id 的添加路径一致。
    func applyRuleUpdates(
        _ catalogSources: [CatalogSource],
        existingSources: [Source]
    ) async throws -> AppliedCatalogRuleUpdates {
        let existingByID: [String: Source] = Dictionary(existingSources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let updatedAt: Date = self.now()
        var materialized: [Source] = []
        var fingerprints: [String: String] = [:]
        var failures: [String: String] = [:]
        for catalogSource: CatalogSource in catalogSources {
            guard let existing: Source = existingByID[catalogSource.id] else {
                continue
            }
            do {
                let source: Source = try self.catalogSourceMaterializer.source(
                    from: catalogSource,
                    createdAt: existing.createdAt,
                    updatedAt: updatedAt,
                    enabled: existing.enabled,
                    origin: existing.origin
                )
                materialized.append(source)
                fingerprints[source.id] = Self.ruleFingerprint(of: catalogSource)
            } catch {
                // 不记：失败写进返回的 failures，由调用方记 catalog-source-update-failed
                failures[catalogSource.id] = String(describing: error)
            }
        }
        try self.sourceRepository.saveCatalogSources(materialized, fingerprintsBySourceID: fingerprints)
        let appliedIDs: Set<String> = Set(materialized.map(\.id))
        self.stampCatalogRevisions(Self.revisions(of: catalogSources.filter { appliedIDs.contains($0.id) }))
        return AppliedCatalogRuleUpdates(sources: materialized, failuresBySourceID: failures)
    }

    func stampCatalogRuleFingerprints(_ fingerprintsBySourceID: [String: String]) async throws {
        try self.sourceRepository.stampCatalogRuleFingerprints(fingerprintsBySourceID)
    }

    /// - Parameter origin: 来源出身；从「我的生成」添加时传 `.personalGeneration`，本地副本才会随服务器裁决清理。
    func execute(
        _ catalogSource: CatalogSource,
        origin: SourceOrigin? = nil
    ) async throws -> AddCatalogSourceResult {
        let fingerprint: String = Self.ruleFingerprint(of: catalogSource)
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
                try self.sourceRepository.saveCatalogSources(
                    [currentCatalogSource],
                    fingerprintsBySourceID: [currentCatalogSource.id: fingerprint]
                )
            } else {
                try self.sourceRepository.stampCatalogRuleFingerprints([currentCatalogSource.id: fingerprint])
            }
            self.stampCatalogRevisions(Self.revisions(of: [catalogSource]))

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
        // 中文注释：规则目录里点了「取消」或超过总时限，即使第一页已经取到也不入库——
        // 否则用户以为取消了，来源却悄悄加上（docs/design/Catalog-Page-Redesign-Design.md 2.4）。
        try Task.checkCancellation()
        try self.sourceRepository.saveCatalogSources([source], fingerprintsBySourceID: [source.id: fingerprint])
        self.stampCatalogRevisions(Self.revisions(of: [catalogSource]))
        return AddCatalogSourceResult(source: source, listOutput: listOutput)
    }

    private static func revisions(of catalogSources: [CatalogSource]) -> [String: String] {
        var revisions: [String: String] = [:]
        for catalogSource: CatalogSource in catalogSources {
            if let revision: String = catalogSource.catalogRevision {
                revisions[catalogSource.id] = revision
            }
        }
        return revisions
    }

    /// 中文注释：记规则版本失败不影响添加与跟随本身（问题报告退回按时间对版本），只记日志。
    private func stampCatalogRevisions(_ revisionsBySourceID: [String: String]) {
        guard revisionsBySourceID.isEmpty == false else {
            return
        }
        do {
            try self.sourceRepository.stampCatalogRevisions(revisionsBySourceID)
        } catch {
            AppLog.error(.database, "catalog-revision-stamp-failed", ["count": .int(revisionsBySourceID.count), "error": .error(error)])
        }
    }
}
