protocol SourceCredentialStoring: SourceCredentialProviding, Sendable {
    func save(_ credential: SourceCredential)
    func removeCredential(sourceID: String)
    func credential(sourceID: String) -> SourceCredential?
}
