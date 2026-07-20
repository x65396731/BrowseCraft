protocol SourceCredentialStoring: SourceCredentialProviding {
    func save(_ credential: SourceCredential)
    func removeCredential(sourceID: String)
    func credential(sourceID: String) -> SourceCredential?
}
