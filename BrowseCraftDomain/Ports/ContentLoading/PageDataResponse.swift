import Foundation

public struct PageDataResponse {
    public init(
        data: Data,
        finalURL: URL
    ) {
        self.data = data
        self.finalURL = finalURL
    }

    public let data: Data
    public let finalURL: URL
}
