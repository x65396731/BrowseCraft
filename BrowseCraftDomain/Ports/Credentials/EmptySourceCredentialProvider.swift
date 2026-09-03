import Foundation

public struct EmptySourceCredentialProvider: SourceCredentialProviding {
    public init() {}

    public func cookieHeader(for context: SourceRequestContext, url: URL) -> String? {
        return nil
    }

    public func headerOverrides(for context: SourceRequestContext, url: URL) -> [String: String] {
        return [:]
    }

    public func token(for sourceID: String, key: String) -> String? {
        return nil
    }

    public func storageValue(for sourceID: String, storage: SourceCredentialStorage, key: String) -> String? {
        return nil
    }
}
