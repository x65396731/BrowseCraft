import SwiftUI
import WebKit
import WebUI

// 中文注释：临时资源历史详情里「打开资源」用的网页视图。原先与已删除的 ComicDiscoveryView 同住一个文件（2026-10-10 删死代码时搬出）。
struct ComicDiscoveryWebResourceView: View {
    @StateObject private var coordinator: ComicDiscoveryWebResourceCoordinator = ComicDiscoveryWebResourceCoordinator()

    let url: URL
    let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

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
            .background(CatalogPalette.plainBackground)
        }
        .navigationTitle(self.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toolbar(proxy: WebViewProxy) -> some View {
        HStack(spacing: 12) {
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
private final class ComicDiscoveryWebResourceCoordinator: NSObject, ObservableObject, WKUIDelegate, WKNavigationDelegate {
    let configuration: WKWebViewConfiguration

    override init() {
        let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
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
}
