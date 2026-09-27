import BrowseCraftAPIKit
import Foundation

/// `PortalAccountFetching` 的 PortalCore 适配器（`GET /v1/account`、`GET /v1/account/ledger`）。
struct APIKitPortalAccountService: PortalAccountFetching {
    private let api: PortalAccountAPI

    init(api: PortalAccountAPI) {
        self.api = api
    }

    func fetchAccount(accessToken: String) async throws -> PortalAccountSnapshot {
        return try await self.mapErrors {
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
        }
    }

    func fetchLedger(accessToken: String, cursor: String?) async throws -> CoinLedgerPage {
        return try await self.mapErrors {
            let page: PortalCoinLedgerPage = try await self.api.fetchLedger(accessToken: accessToken, cursor: cursor)
            return CoinLedgerPage(
                entries: page.entries.map { entry in
                    CoinLedgerEntry(
                        id: entry.id,
                        delta: entry.delta,
                        reason: Self.reason(entry.reason),
                        balanceAfter: entry.balanceAfter,
                        createdAt: entry.createdAt
                    )
                },
                nextCursor: page.nextCursor
            )
        }
    }

    private static func reason(_ reason: PortalCoinLedgerReason) -> CoinLedgerReason {
        switch reason {
        case .signupGrant:
            return .signupGrant
        case .adReward:
            return .adReward
        case .generationNormal:
            return .generationNormal
        case .generationHard:
            return .generationHard
        case .zeroCostRefund:
            return .zeroCostRefund
        case .manualAdjustment:
            return .manualAdjustment
        case .unknown(let rawValue):
            return .unknown(rawValue)
        }
    }

    private func mapErrors<Value>(_ operation: () async throws -> Value) async throws -> Value {
        do {
            return try await operation()
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
