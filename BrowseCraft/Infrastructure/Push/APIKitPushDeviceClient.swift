import BrowseCraftAPIKit
import Foundation

/// `PushDeviceRegistering` 的 PortalCore 适配器（`BC-PREFLIGHT-057`）。
struct APIKitPushDeviceClient: PushDeviceRegistering {
    private let api: PortalPushAPI

    init(api: PortalPushAPI) {
        self.api = api
    }

    func register(
        deviceToken: String,
        environment: PushEnvironment,
        accessToken: String
    ) async throws {
        do {
            _ = try await self.api.registerDevice(
                deviceToken: deviceToken,
                environment: Self.apiEnvironment(environment),
                accessToken: accessToken
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PortalAPIError {
            throw Self.map(error)
        } catch {
            throw PushDeviceRegistrationError.transport
        }
    }

    func unregister(
        deviceToken: String,
        environment: PushEnvironment,
        accessToken: String
    ) async throws {
        do {
            try await self.api.unregisterDevice(
                deviceToken: deviceToken,
                environment: Self.apiEnvironment(environment),
                accessToken: accessToken
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PortalAPIError {
            throw Self.map(error)
        } catch {
            throw PushDeviceRegistrationError.transport
        }
    }

    private static func apiEnvironment(_ environment: PushEnvironment) -> PortalPushEnvironment {
        switch environment {
        case .sandbox:
            return .sandbox
        case .production:
            return .production
        }
    }

    private static func map(_ error: PortalAPIError) -> PushDeviceRegistrationError {
        switch error {
        case .server(let statusCode, let body):
            if statusCode == 401 {
                return .authRequired
            }
            return .rejected(code: body.code)
        case .unexpectedStatusCode(let statusCode):
            if statusCode == 401 {
                return .authRequired
            }
            return .rejected(code: "HTTP_\(statusCode)")
        case .invalidEndpoint, .invalidHTTPResponse, .requestEncodingFailed,
             .transportFailed, .responseDecodingFailed:
            return .transport
        }
    }
}
