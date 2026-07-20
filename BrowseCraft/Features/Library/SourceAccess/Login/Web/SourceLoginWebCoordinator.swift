import SwiftUI
import WebKit

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
