import Alamofire
import Foundation

/// Production HTTP client backed by Alamofire.
final class AlamofireHTTPClient: HTTPClient {
    func getString(from url: URL) async throws -> String {
        return try await AF.request(url).serializingString().value
    }
}

