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

    init(
        reference: SourceVideoPlaybackReference,
        requestConfig: SourcePlaybackRequestConfig? = nil
    ) {
        let requestConfig: SourcePlaybackRequestConfig? = requestConfig ?? reference.playbackRequestConfig
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
        var allHeaders: [String: String] = BrowserRequestHeaders.Chrome.defaultHeaders(
            for: self.url,
            referer: self.referer,
            includeOrigin: true
        )
        allHeaders = BrowserRequestHeaders.applyingOverrides(self.headers, to: allHeaders)
        if let referer: URL = self.referer,
           BrowserRequestHeaders.containsHeader("Referer", in: allHeaders) == false {
            allHeaders["Referer"] = referer.absoluteString
        }
        if let userAgent: String = self.userAgent,
           BrowserRequestHeaders.containsHeader("User-Agent", in: allHeaders) == false {
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
                            "url=\(Self.safeLogURL(self.request.url)) " +
                            "title=\(self.title)"
                        )
                        #endif
                        self.coordinator.prepareCookies(for: self.request) {
                            proxy.load(request: self.request.urlRequest)
                        }
                    }
                    .onChange(of: self.request) { _, newRequest in
                        #if DEBUG
                        print(
                            "[BrowseCraftVideoWebPlayer] reload " +
                            "url=\(Self.safeLogURL(newRequest.url)) " +
                            "title=\(self.title)"
                        )
                        #endif
                        self.coordinator.prepareCookies(for: newRequest) {
                            proxy.load(request: newRequest.urlRequest)
                        }
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

    private static func safeLogURL(_ url: URL) -> String {
        let host: String = url.host ?? "unknown-host"
        return "\(host)\(url.path)"
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
