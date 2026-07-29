import Foundation

/// Catalog transport is isolated from APIKit and platform frameworks at compile time.
public struct CatalogSource: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let baseURL: String
    public let kind: CatalogSourceKind
    public let ruleJSON: String

    public init(
        id: String,
        name: String,
        baseURL: String,
        kind: CatalogSourceKind,
        ruleJSON: String
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.kind = kind
        self.ruleJSON = ruleJSON
    }
}

public enum CatalogSourceKind: String, Codable, Hashable, Sendable {
    case comic
    case rss
    case video
}
