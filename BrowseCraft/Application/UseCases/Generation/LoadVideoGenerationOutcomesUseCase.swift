import BrowseCraftDomain
import Foundation

/// 个人生成结果的读取结果：未登录与「登录了但为空」要分开呈现。
enum VideoGenerationOutcomesLoad: Hashable, Sendable {
    case authRequired
    case loaded([VideoGenerationOutcome])
    case failed(code: String)
}

/// 读取当前用户的规则生成终态（`BC-PREFLIGHT-056`）。
///
/// 中文注释：与任务提交共用同一凭据来源；没有有效 access token 时不发请求，直接返回
/// `authRequired`——「我的生成」分组据此显示登录提示而不是空列表。
/// 成功任务附带的加密规则在这里解密成 `CatalogSource`（与复用路径同一解密器、同一
/// `importRuleJSON` 规则，`BC-PREFLIGHT-055`）；解不开的只是 `catalogSource == nil`，
/// 不影响其它条目。
struct LoadVideoGenerationOutcomesUseCase: Sendable {
    private let outcomesClient: any VideoGenerationOutcomesFetching
    private let accessTokenProvider: any PortalAccessTokenProviding
    private let catalogRuleDecryptor: CatalogRuleDecryptor

    init(
        outcomesClient: any VideoGenerationOutcomesFetching,
        accessTokenProvider: any PortalAccessTokenProviding,
        catalogRuleDecryptor: CatalogRuleDecryptor = CatalogRuleDecryptor()
    ) {
        self.outcomesClient = outcomesClient
        self.accessTokenProvider = accessTokenProvider
        self.catalogRuleDecryptor = catalogRuleDecryptor
    }

    func execute() async -> VideoGenerationOutcomesLoad {
        guard let accessToken: String = await self.accessTokenProvider.validAccessToken() else {
            return .authRequired
        }
        do {
            let outcomes: [VideoGenerationOutcome] = try await self.outcomesClient.fetchOutcomes(
                accessToken: accessToken
            )
            return .loaded(outcomes.map(self.resolvingCatalogSource))
        } catch let error as VideoGenerationOutcomesClientError {
            switch error {
            case .authRequired:
                return .authRequired
            case .notFound:
                return .failed(code: "not-found")
            case .server(let code):
                return .failed(code: code)
            case .transport:
                return .failed(code: "transport")
            }
        } catch is CancellationError {
            return .failed(code: "cancelled")
        } catch {
            return .failed(code: AppLog.safeErrorCode(error))
        }
    }

    private func resolvingCatalogSource(_ outcome: VideoGenerationOutcome) -> VideoGenerationOutcome {
        guard outcome.didSucceed, let stored: VideoGenerationReusedCatalogSource = outcome.source,
              let kind: CatalogSourceKind = CatalogSourceKind(rawValue: stored.kind) else {
            return outcome
        }
        do {
            let decrypted: CatalogRuleJSONValue = try self.catalogRuleDecryptor.decrypt(stored.encryptedRule)
            let data: Data = try JSONEncoder().encode(decrypted.importRuleJSON)
            var resolved: VideoGenerationOutcome = outcome
            resolved.catalogSource = CatalogSource(
                id: stored.catalogSourceID,
                name: stored.name,
                baseURL: stored.baseURL,
                kind: kind,
                ruleJSON: String(decoding: data, as: UTF8.self)
            )
            return resolved
        } catch {
            AppLog.error(.push, event: "outcome-source-decrypt-failed", metadata: ["error": AppLog.safeErrorCode(error)])
            return outcome
        }
    }
}

/// 本人删除一条生成结果（服务端软删除）。
struct HideVideoGenerationOutcomeUseCase: Sendable {
    enum Result: Hashable, Sendable {
        case hidden
        case authRequired
        case failed(code: String)
    }

    private let outcomesClient: any VideoGenerationOutcomesFetching
    private let accessTokenProvider: any PortalAccessTokenProviding

    init(
        outcomesClient: any VideoGenerationOutcomesFetching,
        accessTokenProvider: any PortalAccessTokenProviding
    ) {
        self.outcomesClient = outcomesClient
        self.accessTokenProvider = accessTokenProvider
    }

    func execute(jobID: UUID) async -> Result {
        guard let accessToken: String = await self.accessTokenProvider.validAccessToken() else {
            return .authRequired
        }
        do {
            try await self.outcomesClient.hideOutcome(jobID: jobID, accessToken: accessToken)
            return .hidden
        } catch let error as VideoGenerationOutcomesClientError {
            switch error {
            case .authRequired:
                return .authRequired
            case .notFound:
                // 中文注释：服务端已经没有这条（或不属于本人）——对用户而言就是删掉了。
                return .hidden
            case .server(let code):
                return .failed(code: code)
            case .transport:
                return .failed(code: "transport")
            }
        } catch is CancellationError {
            return .failed(code: "cancelled")
        } catch {
            return .failed(code: AppLog.safeErrorCode(error))
        }
    }
}
