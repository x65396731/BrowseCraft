import Foundation

public struct PageContentResponse: Sendable {
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
