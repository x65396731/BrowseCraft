import BrowseCraftCore
import SwiftUI
import WebKit
import WebUI

struct VideoWebPlayerRequest: Equatable {
    var url: URL
    var headers: [String: String]
    var referer: URL?
    var userAgent: String?

    init(
        url: URL,
        headers: [String: String] = [:],
        referer: URL? = nil,
        userAgent: String? = nil
    ) {
        self.url = url
        self.headers = headers
        self.referer = referer
        self.userAgent = userAgent
    }

    init(reference: SourceVideoPlaybackReference) {
        let requestConfig: SourcePlaybackRequestConfig? = reference.playbackRequestConfig
        self.init(
            url: Self.webPlaybackURL(for: reference),
            headers: requestConfig?.headers ?? [:],
            referer: requestConfig?.referer,
            userAgent: requestConfig?.userAgent
        )
    }

    private static func webPlaybackURL(for reference: SourceVideoPlaybackReference) -> URL {
        guard reference.candidateMediaKind == .iframePlayer,
              let candidateMediaURL: URL = reference.candidateMediaURL,
              Self.isYouTubeURL(candidateMediaURL),
              Self.isYouTubeURL(reference.playPageURL) else {
            return reference.candidateMediaURL ?? reference.playPageURL
        }

        return reference.playPageURL
    }

    private static func isYouTubeURL(_ url: URL) -> Bool {
        guard let host: String = url.host?.lowercased() else {
            return false
        }

        return host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com"
            || host.hasSuffix(".youtube-nocookie.com")
    }

    var urlRequest: URLRequest {
        var request: URLRequest = URLRequest(url: self.url)
        var allHeaders: [String: String] = self.headers
        if let referer: URL = self.referer,
           allHeaders.keys.contains(where: { $0.caseInsensitiveCompare("Referer") == .orderedSame }) == false {
            allHeaders["Referer"] = referer.absoluteString
        }
        if let userAgent: String = self.userAgent,
           allHeaders.keys.contains(where: { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }) == false {
            allHeaders["User-Agent"] = userAgent
        }
        request.allHTTPHeaderFields = allHeaders.isEmpty ? nil : allHeaders
        return request
    }
}

// 中文注释：VideoWebPlayerView 是 WebUI/WKWebView 的物理层封装；和 VideoNativePlayerView 平行。
struct VideoWebPlayerView<Controls: View>: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var coordinator: VideoWebPlayerCoordinator

    let request: VideoWebPlayerRequest
    let title: String
    let controls: () -> Controls
    let onClose: () -> Void

    init(
        request: VideoWebPlayerRequest,
        title: String,
        @ViewBuilder controls: @escaping () -> Controls,
        onClose: @escaping () -> Void
    ) {
        self.request = request
        self.title = title
        self.controls = controls
        self.onClose = onClose
        _coordinator = StateObject(wrappedValue: VideoWebPlayerCoordinator(request: request))
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
                        #if DEBUG
                        print(
                            "[BrowseCraftVideoWebPlayer] appear/load " +
                            "url=\(self.request.url.absoluteString) " +
                            "title=\(self.title)"
                        )
                        #endif
                        proxy.load(request: self.request.urlRequest)
                    }
                    .onChange(of: self.request) { _, newRequest in
                        #if DEBUG
                        print(
                            "[BrowseCraftVideoWebPlayer] reload " +
                            "url=\(newRequest.url.absoluteString) " +
                            "title=\(self.title)"
                        )
                        #endif
                        proxy.load(request: newRequest.urlRequest)
                    }
                    .ignoresSafeArea(edges: .bottom)

                self.controls()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.bar)
            }
            .background(Color(.systemBackground))
        }
        .alert(
            "",
            isPresented: self.$coordinator.isShowingDialog,
            presenting: self.coordinator.dialog
        ) { dialog in
            if case .prompt(_, let defaultText, _) = dialog {
                TextField(defaultText, text: self.$coordinator.promptInput)
            }
            Button("OK") {
                self.coordinator.confirmDialog()
            }
            if dialog.needsCancel {
                Button("Cancel", role: .cancel) {
                    self.coordinator.cancelDialog()
                }
            }
        } message: { dialog in
            Text(dialog.message)
        }
    }

    private func toolbar(proxy: WebViewProxy) -> some View {
        HStack(spacing: 12) {
            Button {
                self.onClose()
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
                Text((proxy.url ?? self.request.url).host() ?? self.request.url.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                self.openURL(proxy.url ?? self.request.url)
            } label: {
                Label("Open in Safari", systemImage: "safari")
                    .labelStyle(.iconOnly)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

@MainActor
final class VideoWebPlayerCoordinator: NSObject, ObservableObject {
    enum Dialog {
        case alert(String, CheckedContinuation<Void, Never>)
        case confirm(String, CheckedContinuation<Bool, Never>)
        case prompt(String, String, CheckedContinuation<String?, Never>)

        var needsCancel: Bool {
            switch self {
            case .alert:
                return false
            case .confirm, .prompt:
                return true
            }
        }

        var message: String {
            switch self {
            case .alert(let message, _):
                return message
            case .confirm(let message, _):
                return message
            case .prompt(let prompt, _, _):
                return prompt
            }
        }
    }

    @Published var dialog: Dialog?
    @Published var isShowingDialog: Bool = false
    @Published var promptInput: String = ""

    let configuration: WKWebViewConfiguration
    private let initialHost: String?

    init(request: VideoWebPlayerRequest) {
        let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        if let userAgent: String = request.userAgent {
            configuration.applicationNameForUserAgent = userAgent
        }
        self.configuration = configuration
        self.initialHost = request.url.host?.lowercased()
        super.init()
    }

    func confirmDialog() {
        guard let dialog: Dialog = self.dialog else {
            return
        }

        self.isShowingDialog = false
        self.dialog = nil

        switch dialog {
        case .alert(_, let continuation):
            continuation.resume()
        case .confirm(_, let continuation):
            continuation.resume(returning: true)
        case .prompt(_, _, let continuation):
            continuation.resume(returning: self.promptInput)
        }
    }

    func cancelDialog() {
        guard let dialog: Dialog = self.dialog else {
            return
        }

        self.isShowingDialog = false
        self.dialog = nil

        switch dialog {
        case .alert(_, let continuation):
            continuation.resume()
        case .confirm(_, let continuation):
            continuation.resume(returning: false)
        case .prompt(_, _, let continuation):
            continuation.resume(returning: nil)
        }
    }

    private func showDialog(_ dialog: Dialog) {
        self.dialog = dialog
        self.isShowingDialog = true
    }
}

extension VideoWebPlayerCoordinator: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            guard self.shouldAllowMainFrameNavigation(to: navigationAction.request.url) else {
                #if DEBUG
                print(
                    "[BrowseCraftVideoWebPlayer] block-target-blank " +
                    "url=\(navigationAction.request.url?.absoluteString ?? "nil")"
                )
                #endif
                return nil
            }

            #if DEBUG
            print(
                "[BrowseCraftVideoWebPlayer] target-blank " +
                "url=\(navigationAction.request.url?.absoluteString ?? "nil")"
            )
            #endif
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async {
        await withCheckedContinuation { continuation in
            self.showDialog(.alert(message, continuation))
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            self.showDialog(.confirm(message, continuation))
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        await withCheckedContinuation { continuation in
            self.promptInput = defaultText ?? ""
            self.showDialog(.prompt(prompt, defaultText ?? "", continuation))
        }
    }
}

extension VideoWebPlayerCoordinator: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        preferences.preferredContentMode = .mobile
        guard let scheme: String = navigationAction.request.url?.scheme?.lowercased() else {
            return (.cancel, preferences)
        }

        if ["http", "https", "blob", "file", "about"].contains(scheme) {
            if navigationAction.targetFrame?.isMainFrame != false,
               self.shouldAllowMainFrameNavigation(to: navigationAction.request.url) == false {
                #if DEBUG
                print(
                    "[BrowseCraftVideoWebPlayer] block-main-frame " +
                    "url=\(navigationAction.request.url?.absoluteString ?? "nil")"
                )
                #endif
                return (.cancel, preferences)
            }

            #if DEBUG
            if navigationAction.targetFrame == nil {
                print(
                    "[BrowseCraftVideoWebPlayer] allow-new-frame " +
                    "url=\(navigationAction.request.url?.absoluteString ?? "nil")"
                )
            }
            #endif
            return (.allow, preferences)
        }

        #if DEBUG
        print(
            "[BrowseCraftVideoWebPlayer] cancel-navigation " +
            "scheme=\(scheme) url=\(navigationAction.request.url?.absoluteString ?? "nil")"
        )
        #endif
        return (.cancel, preferences)
    }

    private func shouldAllowMainFrameNavigation(to url: URL?) -> Bool {
        guard let url: URL,
              let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host: String = url.host?.lowercased(),
              let initialHost: String = self.initialHost else {
            return true
        }

        if self.isYouTubeHost(host), self.isYouTubeHost(initialHost) {
            return true
        }

        return host == initialHost
            || host.hasSuffix(".\(initialHost)")
            || initialHost.hasSuffix(".\(host)")
    }

    private func isYouTubeHost(_ host: String) -> Bool {
        return host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com"
            || host.hasSuffix(".youtube-nocookie.com")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        #if DEBUG
        print(
            "[BrowseCraftVideoWebPlayer] did-finish " +
            "url=\(webView.url?.absoluteString ?? "nil") title=\(webView.title ?? "nil")"
        )
        #endif
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        #if DEBUG
        print(
            "[BrowseCraftVideoWebPlayer] did-fail " +
            "url=\(webView.url?.absoluteString ?? "nil") error=\(error.localizedDescription)"
        )
        #endif
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        #if DEBUG
        print(
            "[BrowseCraftVideoWebPlayer] did-fail-provisional " +
            "url=\(webView.url?.absoluteString ?? "nil") error=\(error.localizedDescription)"
        )
        #endif
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        #if DEBUG
        print(
            "[BrowseCraftVideoWebPlayer] web-content-terminated " +
            "url=\(webView.url?.absoluteString ?? "nil")"
        )
        #endif
        webView.reload()
    }
}
