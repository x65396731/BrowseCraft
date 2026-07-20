import SwiftUI
import WebKit
import WebUI

struct RSSOriginalWebView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator: RSSOriginalWebCoordinator = RSSOriginalWebCoordinator()

    let url: URL
    let title: String

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
                        proxy.load(request: URLRequest(url: self.url))
                    }
                    .ignoresSafeArea(edges: .bottom)
            }
            .background(Color(.systemBackground))
        }
    }

    private func toolbar(proxy: WebViewProxy) -> some View {
        HStack(spacing: 12) {
            Button {
                self.dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }

            Divider()
                .frame(height: 20)

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

            VStack(alignment: .leading, spacing: 2) {
                Text(proxy.title?.isEmpty == false ? proxy.title ?? self.title : self.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text((proxy.url ?? self.url).host() ?? self.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

@MainActor
private final class RSSOriginalWebCoordinator: NSObject, ObservableObject, WKUIDelegate, WKNavigationDelegate {
    let configuration: WKWebViewConfiguration
    private var isLoadingHTTPSUpgrade: Bool = false

    override init() {
        let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        self.configuration = configuration

        super.init()
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

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.targetFrame?.isMainFrame == true,
              let navigationURL: URL = navigationAction.request.url,
              let upgradedURL: URL = Self.httpsURLIfNeeded(from: navigationURL) else {
            decisionHandler(.allow)
            return
        }

        self.isLoadingHTTPSUpgrade = true
        decisionHandler(.cancel)
        webView.load(URLRequest(url: upgradedURL))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        self.isLoadingHTTPSUpgrade = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        guard self.shouldIgnoreInterruptedNavigation(error) == false else {
            return
        }

        self.isLoadingHTTPSUpgrade = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        guard self.shouldIgnoreInterruptedNavigation(error) == false else {
            return
        }

        self.isLoadingHTTPSUpgrade = false
    }

    private static func httpsURLIfNeeded(from url: URL) -> URL? {
        guard url.scheme?.lowercased() == "http",
              var components: URLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = "https"
        return components.url
    }

    private func shouldIgnoreInterruptedNavigation(_ error: Error) -> Bool {
        guard self.isLoadingHTTPSUpgrade else {
            return false
        }

        let nsError: NSError = error as NSError
        return (nsError.domain == "WebKitErrorDomain" && nsError.code == 102)
            || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
    }
}
