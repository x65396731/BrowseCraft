import Foundation

struct SourceLoginCredentialBuilder {
    func build(
        state: LibrarySourceLoginState,
        cookies: [HTTPCookie],
        storage: SourceLoginStorageSnapshot
    ) throws -> SourceCredential {
        let accessToken: String? = storage.localStorage["accessToken"]
            ?? storage.sessionStorage["accessToken"]
        let refreshToken: String? = storage.localStorage["refreshToken"]
            ?? storage.sessionStorage["refreshToken"]
        let credential: SourceCredential = SourceCredential(
            sourceID: state.sourceID,
            baseURL: state.baseURL,
            cookies: cookies,
            accessToken: accessToken,
            refreshToken: refreshToken,
            localStorage: storage.localStorage,
            sessionStorage: storage.sessionStorage,
            origin: .webView
        )

        guard cookies.isEmpty == false
            || accessToken?.isEmpty == false
            || refreshToken?.isEmpty == false
            || storage.localStorage.isEmpty == false
            || storage.sessionStorage.isEmpty == false else {
            throw SourceLoginSessionError.noCredentialMaterial
        }

        return credential
    }
}
