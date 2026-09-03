import BrowseCraftAPIKit
import Foundation

/// `VideoGenerationTaskCreating` 的 PortalCore 适配器（`BC-PREFLIGHT-044`）。
struct APIKitVideoGenerationTaskClient: VideoGenerationTaskCreating {
    private let api: PortalRuleGenerationAPI

    init(api: PortalRuleGenerationAPI) {
        self.api = api
    }

    func createVideoTask(
        entryURL: String,
        accessToken: String
    ) async throws -> VideoGenerationTaskCreation {
        PortalSessionDiagnostics.notice(
            "event=request-start operation=rule-generation-submit " +
                "path=\(PortalAPIPath.ruleGenerations)"
        )
        do {
            let submit: PortalRuleGenerationSubmitResponse = try await self.api.submitVideo(
                entryURL: entryURL,
                accessToken: accessToken
            )
            switch submit {
            case .accepted(let response):
                PortalSessionDiagnostics.notice(
                    "event=request-success operation=rule-generation-submit " +
                        "jobId=\(response.jobID.uuidString) status=\(response.status)"
                )
                return .queued(
                    VideoGenerationTaskReceipt(
                        jobID: response.jobID,
                        submittedEntryURL: entryURL
                    )
                )
            case .cached(let response):
                PortalSessionDiagnostics.notice(
                    "event=request-success operation=rule-generation-submit " +
                        "status=\(response.status) catalogSourceId=\(response.catalogSourceID)"
                )
                return .reused(
                    VideoGenerationReusedCatalogSource(
                        catalogSourceID: response.catalogSourceID,
                        entryURL: entryURL,
                        name: response.source.name,
                        baseURL: response.source.baseURL,
                        kind: response.source.kind,
                        encryptedRule: EncryptedCatalogRule(
                            version: response.source.encryptedRule.version,
                            keyId: response.source.encryptedRule.keyID,
                            nonce: response.source.encryptedRule.nonce,
                            ciphertext: response.source.encryptedRule.ciphertext
                        )
                    )
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PortalAPIError {
            PortalSessionDiagnostics.notice(
                "event=request-failure operation=rule-generation-submit error=\(error)"
            )
            throw Self.map(error)
        } catch {
            throw VideoGenerationTaskClientError.transport
        }
    }

    private static func map(_ error: PortalAPIError) -> VideoGenerationTaskClientError {
        switch error {
        case .server(let statusCode, let body):
            if statusCode == 429 || body.code == PortalRuleGenerationErrorCode.activeJobLimit {
                return .activeJobLimit
            }
            if statusCode == 401 || body.code == PortalRuleGenerationErrorCode.authRequired {
                return .authRequired
            }
            return .server(code: body.code)
        case .unexpectedStatusCode(let statusCode):
            if statusCode == 401 {
                return .authRequired
            }
            if statusCode == 429 {
                return .activeJobLimit
            }
            return .server(code: "HTTP_\(statusCode)")
        case .invalidEndpoint, .invalidHTTPResponse, .requestEncodingFailed,
             .transportFailed, .responseDecodingFailed:
            return .transport
        }
    }
}
