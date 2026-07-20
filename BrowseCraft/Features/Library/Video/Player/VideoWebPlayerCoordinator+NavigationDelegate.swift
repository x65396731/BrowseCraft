import WebKit

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

        if ["http", "https", "blob", "file", "about", "data"].contains(scheme) {
            if navigationAction.targetFrame?.isMainFrame != false,
               self.shouldAllowMainFrameNavigation(to: navigationAction.request.url) == false {
                #if DEBUG
                print(
                    "[BrowseCraftVideoWebPlayer] block-main-frame " +
                    "url=\(self.safeLogURL(navigationAction.request.url))"
                )
                #endif
                return (.cancel, preferences)
            }

            #if DEBUG
            if navigationAction.targetFrame == nil {
                print(
                    "[BrowseCraftVideoWebPlayer] allow-new-frame " +
                    "url=\(self.safeLogURL(navigationAction.request.url))"
                )
            }
            #endif
            return (.allow, preferences)
        }

        #if DEBUG
        print(
            "[BrowseCraftVideoWebPlayer] cancel-navigation " +
            "scheme=\(scheme) url=\(self.safeLogURL(navigationAction.request.url))"
        )
        #endif
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

        if self.isYouTubeHost(host), self.isYouTubeHost(initialHost) {
            return true
        }

        if self.isAbyssPlayerHost(host), self.isAbyssPlayerHost(initialHost) {
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

    private func isAbyssPlayerHost(_ host: String) -> Bool {
        return host == "abyssplayer.com"
            || host.hasSuffix(".abyssplayer.com")
            || host == "abyss.to"
            || host.hasSuffix(".abyss.to")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        #if DEBUG
        print(
            "[BrowseCraftVideoWebPlayer] did-finish " +
            "url=\(self.safeLogURL(webView.url)) title=\(webView.title ?? "nil")"
        )
        #endif
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        #if DEBUG
        print(
            "[BrowseCraftVideoWebPlayer] did-fail " +
            "url=\(self.safeLogURL(webView.url)) error=\(error.localizedDescription)"
        )
        #endif
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        #if DEBUG
        print(
            "[BrowseCraftVideoWebPlayer] did-fail-provisional " +
            "url=\(self.safeLogURL(webView.url)) error=\(error.localizedDescription)"
        )
        #endif
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        #if DEBUG
        print(
            "[BrowseCraftVideoWebPlayer] web-content-terminated " +
            "url=\(self.safeLogURL(webView.url))"
        )
        #endif
        webView.reload()
    }

    func safeLogURL(_ url: URL?) -> String {
        guard let url: URL else {
            return "nil"
        }
        return "\(url.host ?? "unknown-host")\(url.path)"
    }
}
