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
            return outcomes.map { outcome in
                return VideoGenerationOutcome(
                    jobID: outcome.jobID,
                    entryURL: outcome.entryURL,
                    status: outcome.status,
                    finishedAt: outcome.finishedAt,
                    catalogSourceID: outcome.catalogSourceID,
                    reason: outcome.reason?.rawValue,
                    reasonDetail: outcome.reasonDetail?.rawValue
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PortalAPIError {
            throw Self.map(error)
        } catch {
            throw VideoGenerationOutcomesClientError.transport
        }
    }

    private static func map(_ error: PortalAPIError) -> VideoGenerationOutcomesClientError {
        switch error {
        case .server(let statusCode, let body):
            if statusCode == 401 {
                return .authRequired
            }
            return .server(code: body.code)
        case .unexpectedStatusCode(let statusCode):
            if statusCode == 401 {
                return .authRequired
            }
            return .server(code: "HTTP_\(statusCode)")
        case .invalidEndpoint, .invalidHTTPResponse, .requestEncodingFailed,
             .transportFailed, .responseDecodingFailed:
            return .transport
        }
    }
}
