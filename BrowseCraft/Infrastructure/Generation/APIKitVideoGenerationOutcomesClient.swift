import BrowseCraftAPIKit
import Foundation

/// `VideoGenerationOutcomesFetching` 的 PortalCore 适配器（`BC-PREFLIGHT-056`）。
struct APIKitVideoGenerationOutcomesClient: VideoGenerationOutcomesFetching {
    private let api: PortalRuleGenerationAPI

    init(api: PortalRuleGenerationAPI) {
        self.api = api
    }

    func fetchOutcomes(accessToken: String) async throws -> [VideoGenerationOutcome] {
        do {
            let outcomes: [PortalRuleGenerationOutcome] = try await self.api.listOutcomes(
                accessToken: accessToken
            )
            return outcomes.map(Self.map)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PortalAPIError {
            throw Self.map(error)
        } catch {
            throw VideoGenerationOutcomesClientError.transport
        }
    }

    func hideOutcome(jobID: UUID, accessToken: String) async throws {
        do {
            try await self.api.hideOutcome(jobID: jobID, accessToken: accessToken)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PortalAPIError {
            throw Self.map(error)
        } catch {
            throw VideoGenerationOutcomesClientError.transport
        }
    }

    /// 中文注释：用 Sendable 的值类型解析策略代替 `ISO8601DateFormatter` 静态实例（后者是非 Sendable 类，
    /// 不能做全局共享）。固定输入对照：`+00:00`、`Z`、`+0800`、带/不带小数秒的结果与原 formatter 一致，
    /// 仅小数秒保留到微秒而非毫秒。
    private static let isoParser: Date.ISO8601FormatStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let isoParserWithoutFraction: Date.ISO8601FormatStyle = Date.ISO8601FormatStyle()

    static func date(from text: String?) -> Date? {
        guard let text else {
            return nil
        }
        return (try? Self.isoParser.parse(text)) ?? (try? Self.isoParserWithoutFraction.parse(text))
    }

    private static func map(_ outcome: PortalRuleGenerationOutcome) -> VideoGenerationOutcome {
        return VideoGenerationOutcome(
            jobID: outcome.jobID,
            entryURL: outcome.entryURL,
            status: outcome.status,
            finishedAt: outcome.finishedAt,
            catalogSourceID: outcome.catalogSourceID,
            reason: outcome.reason?.rawValue,
            reasonDetail: outcome.reasonDetail?.rawValue,
            expiresAt: Self.date(from: outcome.expiresAt),
            source: outcome.source.map { stored in
                return VideoGenerationReusedCatalogSource(
                    catalogSourceID: stored.id,
                    entryURL: outcome.entryURL ?? stored.baseURL,
                    name: stored.name,
                    baseURL: stored.baseURL,
                    kind: stored.kind,
                    encryptedRule: EncryptedCatalogRule(
                        version: stored.encryptedRule.version,
                        keyId: stored.encryptedRule.keyID,
                        nonce: stored.encryptedRule.nonce,
                        ciphertext: stored.encryptedRule.ciphertext
                    )
                )
            }
        )
    }

    private static func map(_ error: PortalAPIError) -> VideoGenerationOutcomesClientError {
        switch error {
        case .server(let statusCode, let body):
            if statusCode == 401 {
                return .authRequired
            }
            if statusCode == 404 {
                return .notFound
            }
            return .server(code: body.code)
        case .unexpectedStatusCode(let statusCode):
            if statusCode == 401 {
                return .authRequired
            }
            if statusCode == 404 {
                return .notFound
            }
            return .server(code: "HTTP_\(statusCode)")
        case .invalidEndpoint, .invalidHTTPResponse, .requestEncodingFailed,
             .transportFailed, .responseDecodingFailed:
            return .transport
        }
    }
}
