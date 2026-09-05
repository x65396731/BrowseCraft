import BrowseCraftCore
import BrowseCraftDomain
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
              let candidateMediaURL: URL = reference.candidateMediaURL else {
            return reference.candidateMediaURL ?? reference.playPageURL
        }

        if reference.status == .pageOnly {
            return reference.playPageURL
        }

        if Self.isYouTubeURL(candidateMediaURL),
           Self.isYouTubeURL(reference.playPageURL) {
            return reference.playPageURL
        }

        return candidateMediaURL
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

    func urlRequest(
        browserRequestHeaderProvider: any BrowserRequestHeaderProviding
    ) -> URLRequest {
        var request: URLRequest = URLRequest(url: self.url)
        var allHeaders: [String: String] = browserRequestHeaderProvider.defaultHeaders(
            for: self.url,
            referer: self.referer,
            includeOrigin: true
        )
        allHeaders = RequestHeaderFields.applyingOverrides(self.headers, to: allHeaders)
        if let referer: URL = self.referer,
           RequestHeaderFields.containsHeader("Referer", in: allHeaders) == false {
            allHeaders["Referer"] = referer.absoluteString
        }
        if let userAgent: String = self.userAgent,
           RequestHeaderFields.containsHeader("User-Agent", in: allHeaders) == false {
            allHeaders["User-Agent"] = userAgent
        }
        request.allHTTPHeaderFields = allHeaders.isEmpty ? nil : allHeaders
        return request
    }
}

// 中文注释：VideoWebPlayerView 是 WebUI/WKWebView 的物理层封装；和 VideoNativePlayerView 平行。
struct VideoWebPlayerView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.browserRequestHeaderProvider) private var browserRequestHeaderProvider
    @StateObject private var coordinator: VideoWebPlayerCoordinator

    let request: VideoWebPlayerRequest
    let title: String
    let onClose: () -> Void

    init(
        request: VideoWebPlayerRequest,
        title: String,
        auditMediaEventHandler: (any VideoWebPlayerUserContentAttaching)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.request = request
        self.title = title
        self.onClose = onClose
        _coordinator = StateObject(
            wrappedValue: VideoWebPlayerCoordinator(
                request: request,
                auditMediaEventHandler: auditMediaEventHandler
            )
        )
    }

    var body: some View {
        WebViewReader { proxy in
            VStack(spacing: 0) {
                self.toolbar(proxy: proxy)

                ProgressView(value: proxy.estimatedProgress)
                    .opacity(proxy.isLoading ? 1 : 0.12)

                ZStack {
                    WebView(configuration: self.coordinator.configuration)
                        .uiDelegate(self.coordinator)
                        .navigationDelegate(self.coordinator)
                        .allowsBackForwardNavigationGestures(true)
                        .allowsLinkPreview(false)
                        .contentInsetAdjustmentBehavior(.never)
                        .refreshable()
                        .onAppear {
                            #if DEBUG
                            AppDebugLog.write(
                                "[BrowseCraftVideoWebPlayer] appear/load " +
                                "url=\(Self.safeLogURL(self.request.url)) " +
                                "title=\(self.title)"
                            )
                            #endif
                            self.coordinator.prepareCookies(for: self.request) {
                                proxy.load(
                                    request: self.request.urlRequest(
                                        browserRequestHeaderProvider: self.browserRequestHeaderProvider
                                    )
                                )
                            }
                        }
                        .onChange(of: self.request) { _, newRequest in
                            #if DEBUG
                            AppDebugLog.write(
                                "[BrowseCraftVideoWebPlayer] reload " +
                                "url=\(Self.safeLogURL(newRequest.url)) " +
                                "title=\(self.title)"
                            )
                            #endif
                            self.coordinator.prepareCookies(for: newRequest) {
                                proxy.load(
                                    request: newRequest.urlRequest(
                                        browserRequestHeaderProvider: self.browserRequestHeaderProvider
                                    )
                                )
                            }
                        }

                    if let failure: VideoPlaybackProviderFailure = self.coordinator.providerFailure {
                        VideoPlaybackProviderFailureCard(
                            failure: failure,
                            retryAction: {
                                self.coordinator.providerFailure = nil
                                proxy.reload()
                            },
                            openInBrowserAction: {
                                self.openURL(failure.url)
                            }
                        )
                    }
                }
                .ignoresSafeArea(edges: .bottom)
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
}

/// 中文注释：外部播放源失败的就地状态卡。持久展示（非 toast），
/// 覆盖播放区但保留工具栏——用户可以重试、换网络后重试，或去系统浏览器
/// 亲手验证"拦的是源站不是应用"。
private struct VideoPlaybackProviderFailureCard: View {
    let failure: VideoPlaybackProviderFailure
    let retryAction: () -> Void
    let openInBrowserAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: self.iconName)
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text(self.failure.title)
                .font(.headline)

            Text(self.failure.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let hint: String = self.failure.hint {
                Text("💡 \(hint)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button {
                    self.retryAction()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    self.openInBrowserAction()
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).opacity(0.6))
    }

    private var iconName: String {
        switch self.failure.kind {
        case .blocked:
            return "shield.slash"
        case .unreachable:
            return "wifi.exclamationmark"
        case .sourceInvalid:
            return "film.stack"
        case .providerError:
            return "exclamationmark.triangle"
        }
    }
}

extension VideoWebPlayerView {
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
