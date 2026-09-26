import BrowseCraftAPIKit
import Foundation

/// `PortalAccountFetching` 的 PortalCore 适配器（`GET /v1/account`）。
struct APIKitPortalAccountService: PortalAccountFetching {
    private let api: PortalAccountAPI

    init(api: PortalAccountAPI) {
        self.api = api
    }

    func fetchAccount(accessToken: String) async throws -> PortalAccountSnapshot {
        do {
            let response: PortalAccountResponse = try await self.api.fetchAccount(accessToken: accessToken)
            return PortalAccountSnapshot(
                userID: response.userID,
                coinBalance: response.coinBalance,
                revision: response.revision,
                pricing: CoinPricing(
                    normal: response.pricing.normal,
                    hard: response.pricing.hard,
                    adReward: response.pricing.adReward
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PortalAPIError {
            switch error {
            case .server(let statusCode, let body):
                if statusCode == 401 {
                    throw PortalAccountClientError.authRequired
                }
                throw PortalAccountClientError.server(code: body.code)
            case .unexpectedStatusCode(let statusCode):
                if statusCode == 401 {
                    throw PortalAccountClientError.authRequired
                }
                throw PortalAccountClientError.server(code: "HTTP_\(statusCode)")
            case .invalidEndpoint, .invalidHTTPResponse, .requestEncodingFailed,
                 .transportFailed, .responseDecodingFailed:
                throw PortalAccountClientError.transport
            }
        } catch {
            throw PortalAccountClientError.transport
        }
    }
}
