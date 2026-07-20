import WebKit

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
                    "url=\(self.safeLogURL(navigationAction.request.url))"
                )
                #endif
                return nil
            }

            #if DEBUG
            print(
                "[BrowseCraftVideoWebPlayer] target-blank " +
                "url=\(self.safeLogURL(navigationAction.request.url))"
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
