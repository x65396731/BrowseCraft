import BrowseCraftLog
import WebKit

extension VideoWebPlayerCoordinator: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        self.attachForDelegateDetaching(webView)
        preferences.preferredContentMode = .mobile
        guard let scheme: String = navigationAction.request.url?.scheme?.lowercased() else {
            return (.cancel, preferences)
        }

        if ["http", "https", "blob", "file", "about", "data"].contains(scheme) {
            if navigationAction.targetFrame?.isMainFrame != false,
               self.shouldAllowMainFrameNavigation(to: navigationAction.request.url) == false {
                self.markExpectedInterruptedMainFrameNavigation()
                #if DEBUG
                AppLog.debug(.playback, "video-web-player-block-main-frame", [
                    "url": .text("\(self.safeLogURL(navigationAction.request.url))")
                ])
                #endif
                return (.cancel, preferences)
            }

            if navigationAction.targetFrame?.isMainFrame == true {
                // 中文注释：`APP-MEMO-018`——声明的 UA 与 WebView 当前值不同时，设上并用同一请求重发。
                if scheme == "http" || scheme == "https",
                   self.applyDeclaredUserAgentIfNeeded(to: webView, reloading: navigationAction.request) {
                    return (.cancel, preferences)
                }
                self.resetMobileAdaptation(in: webView)
            }

            #if DEBUG
            if navigationAction.targetFrame == nil {
                AppLog.debug(.playback, "video-web-player-allow-new-frame", [
                    "url": .text("\(self.safeLogURL(navigationAction.request.url))")
                ])
            }
            #endif
            return (.allow, preferences)
        }

        #if DEBUG
        AppLog.debug(.playback, "video-web-player-cancel-navigation", [
            "scheme": .text("\(scheme)"),
            "url": .text("\(self.safeLogURL(navigationAction.request.url))")
        ])
        #endif
        if navigationAction.targetFrame?.isMainFrame != false {
            self.markExpectedInterruptedMainFrameNavigation()
        }
        return (.cancel, preferences)
    }

    func shouldAllowMainFrameNavigation(to url: URL?) -> Bool {
        guard let url: URL,
              let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host: String = url.host?.lowercased(),
              let initialHost: String = self.initialHost else {
            return true
        }

        if self.shouldBlockLikelyNoiseNavigation(url) {
            return false
        }

        if self.isYouTubeHost(host), self.isYouTubeHost(initialHost) {
            return true
        }

        if self.isAbyssPlayerHost(host), self.isAbyssPlayerHost(initialHost) {
            return true
        }

        return host == initialHost
            || host.hasSuffix(".\(initialHost)")
            || initialHost.hasSuffix(".\(host)")
            || self.isAllowedMobileAlternateHost(host)
    }

    private func isYouTubeHost(_ host: String) -> Bool {
        return host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com"
            || host.hasSuffix(".youtube-nocookie.com")
    }

    private func isAbyssPlayerHost(_ host: String) -> Bool {
        return host == "abyssplayer.com"
            || host.hasSuffix(".abyssplayer.com")
            || host == "abyss.to"
            || host.hasSuffix(".abyss.to")
    }

    /// 中文注释：`BC` 外部播放源失败检测——WKWebView 的主 frame 错误回调看不到
    /// 子 frame（embed iframe），但本回调对子 frame 文档同样触发，是唯一能读到
    /// embed 提供方 HTTP 状态（如 Cloudflare 403）的位置。始终放行，不改变导航行为。
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        #if DEBUG
        AppLog.debug(.playback, "video-web-player-nav-response", [
            "mainFrame": .text("\(navigationResponse.isForMainFrame)"),
            "status": .text("\((navigationResponse.response as? HTTPURLResponse)?.statusCode ?? -1)"),
            "url": .text("\(self.safeLogURL(navigationResponse.response.url))")
        ])
        #endif
        if let httpResponse: HTTPURLResponse = navigationResponse.response as? HTTPURLResponse,
           httpResponse.statusCode >= 400,
           let url: URL = httpResponse.url {
            self.reportHTTPFailure(
                statusCode: httpResponse.statusCode,
                url: url,
                isMainFrame: navigationResponse.isForMainFrame
            )
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        self.cancelEmbedProbe()
        self.clearProviderFailureForNewDocument()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        #if DEBUG
        AppLog.debug(.playback, "video-web-player-did-finish", [
            "url": .text("\(self.safeLogURL(webView.url))"),
            "title": .text("\(webView.title ?? "nil")")
        ])
        self.logViewportMetrics(webView)
        #endif

        self.scheduleMobileAdaptation(in: webView)
        self.scheduleEmbedProbe(in: webView)
        self.markDocumentFinished()
    }

    #if DEBUG
    private func logViewportMetrics(_ webView: WKWebView) {
        Task { @MainActor in
            do {
                let value: Any? = try await webView.evaluateJavaScript(
                    """
                    (() => ({
                      innerWidth: window.innerWidth || 0,
                      documentWidth: document.documentElement
                        ? document.documentElement.clientWidth
                        : 0,
                      scrollWidth: document.documentElement
                        ? document.documentElement.scrollWidth
                        : 0,
                      visualWidth: window.visualViewport
                        ? window.visualViewport.width
                        : 0,
                      viewport: document.querySelector('meta[name="viewport"]')
                        ?.getAttribute('content') || "missing"
                    }))();
                    """
                )
                guard let metrics: [String: Any] = value as? [String: Any] else {
                    return
                }
                AppLog.debug(.playback, "video-web-player-viewport", [
                    "innerWidth": .text("\(String(describing: metrics["innerWidth"] ?? "nil"))"),
                    "documentWidth": .text("\(String(describing: metrics["documentWidth"] ?? "nil"))"),
                    "scrollWidth": .text("\(String(describing: metrics["scrollWidth"] ?? "nil"))"),
                    "visualWidth": .text("\(String(describing: metrics["visualWidth"] ?? "nil"))"),
                    "pageZoom": .text("\(webView.pageZoom)"),
                    "meta": .text("\(String(describing: metrics["viewport"] ?? "nil"))")
                ])
            } catch {
                AppLog.debug(.playback, "video-web-player-viewport-read-failed", ["error": .error(error)])
            }
        }
    }
    #endif

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        guard self.shouldIgnoreInterruptedNavigation(error) == false else {
            return
        }

        // 中文注释：主文档加载到一半失败是播放器状态变化，记 info（Logging-Design.md 第 8 节）。
        AppLog.info(.playback, "video-web-player-did-fail", [
            "url": .path(webView.url),
            "error": .error(error)
        ])
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        guard self.shouldIgnoreInterruptedNavigation(error) == false else {
            return
        }

        // 中文注释：主文档连接层失败（超时/DNS/重置）——疑似网络屏蔽形态。
        self.reportConnectionFailure(error, fallbackURL: webView.url)

        #if DEBUG
        AppLog.debug(.playback, "video-web-player-did-fail-provisional", [
            "url": .text("\(self.safeLogURL(webView.url))"),
            "error": .error(error)
        ])
        #endif
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // 中文注释：网页进程被系统杀掉后自动重载，记 info 便于对上「播放页突然空白」的反馈。
        AppLog.info(.playback, "video-web-player-web-content-terminated", ["url": .path(webView.url)])
        webView.reload()
    }

    func safeLogURL(_ url: URL?) -> String {
        guard let url: URL else {
            return "nil"
        }
        return "\(url.host ?? "unknown-host")\(url.path)"
    }
}
