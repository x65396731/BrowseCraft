import SwiftUI
import WebKit
import WebUI

// 中文注释：SourceLoginView 是漫画、影视、RSS 共用的站点登录 WebUI，并在用户确认后采集当前 Source 会话。
struct SourceLoginView: View {
    @StateObject private var coordinator: SourceLoginWebCoordinator = SourceLoginWebCoordinator()
    @State private var didLoadInitialURL: Bool = false
    @State private var isCapturingCredential: Bool = false
    @State private var captureErrorMessage: String?

    let state: LibrarySourceLoginState
    let cancelAction: () -> Void
    let completeAction: (SourceCredential) -> Void

    var body: some View {
        WebViewReader { proxy in
            VStack(spacing: 0) {
                self.toolbar(proxy: proxy)

                ProgressView(value: proxy.estimatedProgress)
                    .opacity(proxy.isLoading ? 1 : 0.12)

                WebView(configuration: self.coordinator.configuration)
                    .uiDelegate(self.coordinator)
                    .navigationDelegate(self.coordinator)
                    .allowsBackForwardNavigationGestures(true)
                    .allowsLinkPreview(false)
                    .contentInsetAdjustmentBehavior(.never)
                    .refreshable()
                    .onAppear {
                        guard self.didLoadInitialURL == false else {
                            return
                        }

                        self.didLoadInitialURL = true
                        proxy.load(request: URLRequest(url: self.state.loginURL))
                    }
                    .ignoresSafeArea(edges: .bottom)
            }
            .background(Color(.systemBackground))
        }
        .interactiveDismissDisabled()
        .alert("Login Session", isPresented: self.captureErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(self.captureErrorMessage ?? "Unable to save the login session.")
        }
    }

    private func toolbar(proxy: WebViewProxy) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button("Close") {
                    self.cancelAction()
                }
                .disabled(self.isCapturingCredential)

                VStack(alignment: .leading, spacing: 2) {
                    Text(proxy.title?.isEmpty == false ? proxy.title ?? self.state.sourceName : self.state.sourceName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text((proxy.url ?? self.state.loginURL).host() ?? self.state.loginURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task {
                        await self.captureCredential()
                    }
                } label: {
                    if self.isCapturingCredential {
                        ProgressView()
                    } else {
                        Text("Done")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.isCapturingCredential)
            }

            HStack(spacing: 18) {
                Button {
                    proxy.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .labelStyle(.iconOnly)
                }
                .disabled(proxy.canGoBack == false)

                Button {
                    proxy.goForward()
                } label: {
                    Label("Forward", systemImage: "chevron.forward")
                        .labelStyle(.iconOnly)
                }
                .disabled(proxy.canGoForward == false)

                Button {
                    proxy.reload()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }

                Spacer(minLength: 0)

                Text("Sign in to this source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @MainActor
    private func captureCredential() async {
        self.isCapturingCredential = true
        defer { self.isCapturingCredential = false }

        do {
            let credential: SourceCredential = try await self.coordinator.captureCredential(for: self.state)
            self.completeAction(credential)
        } catch {
            self.captureErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var captureErrorBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.captureErrorMessage != nil
            },
            set: { isPresented in
                if isPresented == false {
                    self.captureErrorMessage = nil
                }
            }
        )
    }
}

enum SourceLoginSessionError: LocalizedError {
    case webViewUnavailable
    case noCredentialMaterial
    case invalidStorageResult

    var errorDescription: String? {
        switch self {
        case .webViewUnavailable:
            return "Wait for the login page to finish loading before saving."
        case .noCredentialMaterial:
            return "No login Cookie or configured token was found. Complete login before tapping Done."
        case .invalidStorageResult:
            return "The login page returned an unreadable storage result."
        }
    }
}

struct SourceLoginStorageSnapshot: Equatable {
    let localStorage: [String: String]
    let sessionStorage: [String: String]
}

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

@MainActor
final class SourceLoginWebCoordinator: NSObject, ObservableObject, WKUIDelegate, WKNavigationDelegate {
    let configuration: WKWebViewConfiguration
    private weak var webView: WKWebView?

    override init() {
        let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
        // 中文注释：登录必须使用持久 WebsiteDataStore，才能保留机器人校验、多步跳转和网站会话。
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        self.configuration = configuration

        super.init()
    }

    func captureCredential(for state: LibrarySourceLoginState) async throws -> SourceCredential {
        guard self.webView != nil else {
            throw SourceLoginSessionError.webViewUnavailable
        }

        async let cookies: [HTTPCookie] = self.sourceCookies(for: state)
        async let storage: SourceLoginStorageSnapshot = self.storageSnapshot(keys: state.credentialKeys)
        return try await SourceLoginCredentialBuilder().build(
            state: state,
            cookies: cookies,
            storage: storage
        )
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        self.webView = webView
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        self.webView = webView
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let requestURL: URL = navigationAction.request.url else {
            return nil
        }

        webView.load(URLRequest(url: requestURL))
        return nil
    }

    private func sourceCookies(for state: LibrarySourceLoginState) async -> [HTTPCookie] {
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            self.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        let now: Date = Date()
        return cookies.filter { cookie in
            guard cookie.expiresDate.map({ $0 > now }) ?? true else {
                return false
            }
            return SourceLoginSessionDomainMatcher.matches(cookie: cookie, state: state)
        }
    }

    private func storageSnapshot(keys: [String]) async throws -> SourceLoginStorageSnapshot {
        guard keys.isEmpty == false else {
            return SourceLoginStorageSnapshot(localStorage: [:], sessionStorage: [:])
        }
        guard let webView: WKWebView = self.webView else {
            throw SourceLoginSessionError.webViewUnavailable
        }

        let keysData: Data = try JSONSerialization.data(withJSONObject: keys)
        guard let keysJSON: String = String(data: keysData, encoding: .utf8) else {
            throw SourceLoginSessionError.invalidStorageResult
        }
        let result: Any? = try await webView.evaluateJavaScript(
            """
            (() => {
              const keys = \(keysJSON);
              const read = (storage) => {
                const values = {};
                for (const key of keys) {
                  try {
                    const value = storage.getItem(key);
                    if (typeof value === 'string' && value.length > 0) {
                      values[key] = value;
                    }
                  } catch (_) {}
                }
                return values;
              };
              return JSON.stringify({
                localStorage: read(window.localStorage),
                sessionStorage: read(window.sessionStorage)
              });
            })();
            """
        )
        guard let json: String = result as? String,
              let data: Data = json.data(using: .utf8),
              let object: [String: Any] = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceLoginSessionError.invalidStorageResult
        }

        return SourceLoginStorageSnapshot(
            localStorage: object["localStorage"] as? [String: String] ?? [:],
            sessionStorage: object["sessionStorage"] as? [String: String] ?? [:]
        )
    }
}

enum SourceLoginSessionDomainMatcher {
    static func matches(cookie: HTTPCookie, state: LibrarySourceLoginState) -> Bool {
        let cookieDomain: String = cookie.domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return self.hosts(for: state).contains { host in
            return host == cookieDomain || host.hasSuffix(".\(cookieDomain)")
        }
    }

    static func matches(record: WKWebsiteDataRecord, state: LibrarySourceLoginState) -> Bool {
        let recordDomain: String = record.displayName
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return self.hosts(for: state).contains { host in
            return host == recordDomain
                || host.hasSuffix(".\(recordDomain)")
                || recordDomain.hasSuffix(".\(host)")
        }
    }

    private static func hosts(for state: LibrarySourceLoginState) -> [String] {
        return [state.baseURL.host, state.loginURL.host]
            .compactMap { $0?.lowercased() }
    }
}

@MainActor
struct SourceLoginSessionCleaner {
    func clear(state: LibrarySourceLoginState) async {
        let dataStore: WKWebsiteDataStore = .default()
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        for cookie: HTTPCookie in cookies where SourceLoginSessionDomainMatcher.matches(cookie: cookie, state: state) {
            await withCheckedContinuation { continuation in
                dataStore.httpCookieStore.delete(cookie) {
                    continuation.resume()
                }
            }
        }

        let dataTypes: Set<String> = [WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeSessionStorage]
        let records: [WKWebsiteDataRecord] = await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
                continuation.resume(returning: records)
            }
        }
        let matchingRecords: [WKWebsiteDataRecord] = records.filter {
            SourceLoginSessionDomainMatcher.matches(record: $0, state: state)
        }
        guard matchingRecords.isEmpty == false else {
            return
        }
        await withCheckedContinuation { continuation in
            dataStore.removeData(ofTypes: dataTypes, for: matchingRecords) {
                continuation.resume()
            }
        }
    }
}
