import Foundation

struct EmptySourceCredentialProvider: SourceCredentialProviding {
    func cookieHeader(for context: SourceRequestContext, url: URL) -> String? {
        return nil
    }

    func headerOverrides(for context: SourceRequestContext, url: URL) -> [String: String] {
        return [:]
    }

    func token(for sourceID: String, key: String) -> String? {
        return nil
    }

    func storageValue(for sourceID: String, storage: SourceCredentialStorage, key: String) -> String? {
        return nil
    }
}
