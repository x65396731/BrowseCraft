import Foundation

protocol SourceCredentialProviding {
    func cookieHeader(for context: SourceRequestContext, url: URL) -> String?
    func headerOverrides(for context: SourceRequestContext, url: URL) -> [String: String]
    func token(for sourceID: String, key: String) -> String?
    func storageValue(for sourceID: String, storage: SourceCredentialStorage, key: String) -> String?
}
