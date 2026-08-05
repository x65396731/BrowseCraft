import Foundation
import SwiftUI
import WebKit

@MainActor
final class VideoWebPlayerCoordinator: NSObject, ObservableObject {
    private struct MobileLayoutMetrics {
        var visibleWidth: CGFloat
        var contentWidth: CGFloat
    }

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
    let initialHost: String?
    private var allowedMobileAlternateHosts: Set<String> = []
    private var attemptedMobileAlternateURLs: Set<String> = []
    private var expectedInterruptedMainFrameNavigationCount: Int = 0
    private var mobileAdaptationTask: Task<Void, Never>?

    init(request: VideoWebPlayerRequest) {
        let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // 中文注释：首个文档必须在 WKWebView 创建时就采用移动内容模式；只在导航
        // delegate 中修改偏好会晚于部分站点的 viewport 初始化，导致桌面宽度被裁切。
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        self.configuration = configuration
        self.initialHost = request.url.host?.lowercased()
        super.init()
    }

    /// 中文注释：每次主文档完成后重新开始适配，避免旧页面的延迟测量覆盖新导航。
    func scheduleMobileAdaptation(in webView: WKWebView) {
        self.mobileAdaptationTask?.cancel()
        self.mobileAdaptationTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else {
                return
            }
            if await self.followMobileAlternateIfNeeded(in: webView) {
                return
            }
            await self.fitFixedLayoutToViewIfNeeded(in: webView)
        }
    }

    func resetMobileAdaptation(in webView: WKWebView) {
        self.mobileAdaptationTask?.cancel()
        webView.pageZoom = 1
    }

    /// 中文注释：我们主动 cancel 的主框架跳转会回调 WebKitErrorDomain 102；
    /// 这里记账，避免把预期中的广告/跨站拦截误记成播放器失败。
    func markExpectedInterruptedMainFrameNavigation() {
        self.expectedInterruptedMainFrameNavigationCount += 1
    }

    func shouldIgnoreInterruptedNavigation(_ error: Error) -> Bool {
        guard self.expectedInterruptedMainFrameNavigationCount > 0 else {
            return false
        }

        let nsError: NSError = error as NSError
        let isInterruptedNavigation: Bool =
            (nsError.domain == "WebKitErrorDomain" && nsError.code == 102)
            || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
        guard isInterruptedNavigation else {
            return false
        }

        self.expectedInterruptedMainFrameNavigationCount -= 1
        return true
    }

    /// 中文注释：优先遵循页面自己声明的移动入口。支持同域路径，以及从普通主机
    /// 切换到 m/mobile/touch 子域；不接受页面借 alternate 发起任意跨站导航。
    private func followMobileAlternateIfNeeded(in webView: WKWebView) async -> Bool {
        let viewWidth: CGFloat = webView.bounds.width
        guard viewWidth > 0,
              let currentURL: URL = webView.url,
              let currentHost: String = currentURL.host?.lowercased() else {
            return false
        }
        let physicalWidth: Int = Int(viewWidth.rounded(.down))

        let script: String = #"""
        (() => {
          const physicalWidth = \#(physicalWidth);
          const links = Array.from(
            document.querySelectorAll('link[rel~="alternate"][href][media]')
          );
          const mobile = links.find((link) => {
            const media = String(link.media || "").trim();
            if (!media) return false;
            if (/\bhandheld\b/i.test(media)) return true;
            const maxWidth = media.match(
              /\(\s*max-(?:device-)?width\s*:\s*([0-9.]+)px\s*\)/i
            );
            if (maxWidth && physicalWidth <= Number(maxWidth[1])) return true;
            return false;
          });
          return mobile ? mobile.href : null;
        })();
        """#

        guard let value: Any = try? await webView.evaluateJavaScript(script),
              let alternateString: String = value as? String,
              self.attemptedMobileAlternateURLs.contains(alternateString) == false,
              let alternateURL: URL = URL(string: alternateString),
              alternateURL != currentURL,
              let scheme: String = alternateURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let alternateHost: String = alternateURL.host?.lowercased(),
              self.isAllowedDeclaredAlternateHost(alternateHost, from: currentHost) else {
            return false
        }

        self.attemptedMobileAlternateURLs.insert(alternateString)
        self.allowedMobileAlternateHosts.insert(alternateHost)

        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftVideoWebPlayer] follow-mobile-alternate " +
            "from=\(self.safeLogURL(currentURL)) to=\(self.safeLogURL(alternateURL))"
        )
        #endif

        guard let jsonData: Data = try? JSONSerialization.data(
            withJSONObject: alternateString,
            options: [.fragmentsAllowed]
        ),
              let jsonString: String = String(data: jsonData, encoding: .utf8) else {
            return false
        }

        do {
            _ = try await webView.evaluateJavaScript(
                "window.location.replace(\(jsonString));"
            )
            return true
        } catch {
            return false
        }
    }

    /// 中文注释：没有移动入口时，不猜测站点类名或改写 DOM。等待主结构宽度稳定，
    /// 仅对明显宽于 WebView 的固定桌面布局应用原生 pageZoom。
    private func fitFixedLayoutToViewIfNeeded(in webView: WKWebView) async {
        guard webView.bounds.width > 0, let expectedURL: URL = webView.url else {
            return
        }

        webView.pageZoom = 1
        var previousWidth: CGFloat?
        var stableChecks: Int = 0
        var measuredMetrics: MobileLayoutMetrics?

        for checkIndex in 0..<6 {
            guard Task.isCancelled == false, webView.url == expectedURL else {
                return
            }
            if checkIndex > 0 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard Task.isCancelled == false else {
                    return
                }
            }

            guard let currentMetrics: MobileLayoutMetrics = await self.mobileLayoutMetrics(
                in: webView
            ) else {
                continue
            }
            let currentWidth: CGFloat = currentMetrics.contentWidth
            measuredMetrics = currentMetrics
            if let previousWidth, abs(currentWidth - previousWidth) <= 2 {
                stableChecks += 1
            } else {
                stableChecks = 0
            }
            previousWidth = currentWidth

            if checkIndex >= 2, stableChecks >= 2 {
                break
            }
        }

        guard Task.isCancelled == false,
              webView.url == expectedURL,
              let measuredMetrics,
              measuredMetrics.visibleWidth > 0,
              measuredMetrics.contentWidth > measuredMetrics.visibleWidth * 1.12 else {
            return
        }

        let scale: CGFloat = max(
            0.1,
            min(1, measuredMetrics.visibleWidth / measuredMetrics.contentWidth)
        )
        webView.pageZoom = scale

        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftVideoWebPlayer] fit-fixed-layout " +
            "viewWidth=\(Int(webView.bounds.width)) " +
            "visibleWidth=\(Int(measuredMetrics.visibleWidth)) " +
            "contentWidth=\(Int(measuredMetrics.contentWidth)) zoom=\(scale) " +
            "url=\(self.safeLogURL(expectedURL))"
        )
        #endif
    }

    private func mobileLayoutMetrics(in webView: WKWebView) async -> MobileLayoutMetrics? {
        let script: String = #"""
        (() => {
          const root = document.documentElement;
          const body = document.body;
          const rootWidth = root ? root.getBoundingClientRect().width || 0 : 0;
          const bodyWidth = body ? body.getBoundingClientRect().width || 0 : 0;
          const clientWidth = root ? root.clientWidth || 0 : 0;
          let flowWidth = Math.max(rootWidth, bodyWidth, clientWidth);

          const candidates = body
            ? Array.from(body.querySelectorAll("*")).slice(0, 2500)
            : [];
          for (const element of candidates) {
            const style = getComputedStyle(element);
            if (
              style.display === "none" ||
              style.display === "inline" ||
              style.display === "contents" ||
              style.position === "absolute" ||
              style.position === "fixed"
            ) continue;

            const rect = element.getBoundingClientRect();
            if (!Number.isFinite(rect.width) || rect.width <= flowWidth || rect.height <= 1) {
              continue;
            }

            let ancestor = element.parentElement;
            let isClipped = false;
            while (ancestor && ancestor !== body) {
              const ancestorStyle = getComputedStyle(ancestor);
              const overflow = ancestorStyle.overflowX;
              if (
                overflow !== "visible" &&
                ancestor.getBoundingClientRect().width + 2 < rect.width
              ) {
                isClipped = true;
                break;
              }
              ancestor = ancestor.parentElement;
            }
            if (!isClipped) flowWidth = rect.width;
          }

          const structuralWidth = flowWidth;
          const scrollWidth = root ? root.scrollWidth || 0 : structuralWidth;
          const visibleWidth =
            (window.visualViewport && window.visualViewport.width) ||
            window.innerWidth ||
            clientWidth;
          return {
            visibleWidth,
            contentWidth: Math.max(
              structuralWidth,
              Math.min(scrollWidth, structuralWidth * 1.05)
            )
          };
        })();
        """#

        guard let value: Any = try? await webView.evaluateJavaScript(script),
              let result: [String: Any] = value as? [String: Any],
              let visibleWidth: NSNumber = result["visibleWidth"] as? NSNumber,
              let contentWidth: NSNumber = result["contentWidth"] as? NSNumber else {
            return nil
        }
        return MobileLayoutMetrics(
            visibleWidth: CGFloat(visibleWidth.doubleValue),
            contentWidth: CGFloat(contentWidth.doubleValue)
        )
    }

    func isAllowedMobileAlternateHost(_ host: String) -> Bool {
        return self.allowedMobileAlternateHosts.contains(host.lowercased())
    }

    private func isAllowedDeclaredAlternateHost(
        _ alternateHost: String,
        from currentHost: String
    ) -> Bool {
        if alternateHost == currentHost {
            return true
        }

        let baseHost: Substring = currentHost.hasPrefix("www.")
            ? currentHost.dropFirst(4)
            : currentHost[...]
        return alternateHost == String(baseHost)
            || alternateHost == "www.\(baseHost)"
            || alternateHost == "m.\(baseHost)"
            || alternateHost == "mobile.\(baseHost)"
            || alternateHost == "touch.\(baseHost)"
    }

    /// 中文注释：把本次播放即时解析出的 Cookie 注入 WebKit store，后续 iframe/媒体子请求无需持久化 Cookie 到历史记录。
    func prepareCookies(
        for request: VideoWebPlayerRequest,
        completion: @escaping @MainActor () -> Void
    ) {
        guard let cookieHeader: String = request.headers.first(where: { key, _ in
            return key.caseInsensitiveCompare("Cookie") == .orderedSame
        })?.value else {
            completion()
            return
        }
        let cookies: [HTTPCookie] = self.cookies(from: cookieHeader, url: request.url)
        guard cookies.isEmpty == false else {
            completion()
            return
        }
        let cookieStore: WKHTTPCookieStore = self.configuration.websiteDataStore.httpCookieStore
        let group: DispatchGroup = DispatchGroup()
        for cookie: HTTPCookie in cookies {
            group.enter()
            cookieStore.setCookie(cookie) {
                group.leave()
            }
        }
        group.notify(queue: .main) {
            Task { @MainActor in
                completion()
            }
        }
    }

    private func cookies(from header: String, url: URL) -> [HTTPCookie] {
        guard let host: String = url.host else {
            return []
        }
        return header.split(separator: ";").compactMap { component in
            let pair: [Substring] = component.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else {
                return nil
            }
            let name: String = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value: String = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false else {
                return nil
            }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: host,
                .path: "/",
                .name: name,
                .value: value
            ]
            if url.scheme?.lowercased() == "https" {
                properties[.secure] = "TRUE"
            }
            return HTTPCookie(properties: properties)
        }
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

    func showDialog(_ dialog: Dialog) {
        self.dialog = dialog
        self.isShowingDialog = true
    }
}
