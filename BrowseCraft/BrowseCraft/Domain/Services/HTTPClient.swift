import Foundation

/// Minimal network protocol used by Application use cases.
///
/// The app can use Alamofire in production and a fake client in tests.
protocol HTTPClient {
    func getString(from url: URL) async throws -> String
}

