import Foundation

public struct PageContentResponse {
    public init(
        content: String,
        finalURL: URL
    ) {
        self.content = content
        self.finalURL = finalURL
    }

    public let content: String
    public let finalURL: URL
}
