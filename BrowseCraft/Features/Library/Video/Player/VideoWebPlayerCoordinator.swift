import BrowseCraftRuntime
import Foundation
import SwiftUI
import WebKit

/// 中文注释：只有 audit 模式才向 WKUserContentController 注入观察脚本；正常播放传 nil。
/// 具体 handler 随 Debug 编译，Coordinator 只依赖这个最小合同。
@MainActor
protocol VideoWebPlayerUserContentAttaching: AnyObject {
    func attach(to controller: WKUserContentController)
    func detach()
}

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
    /// 中文注释：外部播放源（embed 提供方）不可达/被拦截时的持久错误态；
    /// 主文档 commit 时清空，重试由视图层清空后 reload。
    @Published var providerFailure: VideoPlaybackProviderFailure?

    let configuration: WKWebViewConfiguration
    let initialHost: String?
    private let mainFrameNavigationNoiseFilter: SourceContentNoiseFilter = SourceContentNoiseFilter()
    private var allowedMobileAlternateHosts: Set<String> = []
    private var attemptedMobileAlternateURLs: Set<String> = []
    private var expectedInterruptedMainFrameNavigationCount: Int = 0
    private var mobileAdaptationTask: Task<Void, Never>?
    private var embedProbeTask: Task<Void, Never>?
    private var embedProbeCompletedURL: URL?

    init(
        request: VideoWebPlayerRequest,
        auditMediaEventHandler: (any VideoWebPlayerUserContentAttaching)? = nil
    ) {
        let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // 中文注释：首个文档必须在 WKWebView 创建时就采用移动内容模式；只在导航
        // delegate 中修改偏好会晚于部分站点的 viewport 初始化，导致桌面宽度被裁切。
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        // 中文注释：BC-EVIDENCE-077.2——只有 audit 模式才注入 playing 观察脚本与消息通道；
        // 正常播放的 configuration 与本改动前逐字节相同。
        if let auditMediaEventHandler {
            auditMediaEventHandler.attach(to: configuration.userContentController)
        }
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

    /// 中文注释：主框架导航先走通用噪声过滤，拦住广告、推广、登录等非播放页跳转；
    /// 之后再执行同域/移动别名白名单，避免误放跨站主页面替换。
    func shouldBlockLikelyNoiseNavigation(_ url: URL) -> Bool {
        let decision: SourceContentNoiseDecision = self.mainFrameNavigationNoiseFilter.decision(
            for: SourceContentNoiseCandidate(
                url: url,
                context: .playbackCandidate
            )
        )
        return decision.action == .discard
    }

    // MARK: - 外部播放源失败检测

    /// 中文注释：主文档开始渲染即离开错误态；随后到达的子 frame 失败会重新报告。
    func clearProviderFailureForNewDocument() {
        guard self.providerFailure != nil else {
            return
        }
        self.providerFailure = nil
    }

    /// 中文注释：HTTP 层失败分类。主 frame 失败一律报告（此时主文档往往就是
    /// embed 提供方或播放页本身）；子 frame 只报告"疑似播放器"的跨站文档——
    /// 同站 iframe 与广告噪声不属于播放源失败。
    func reportHTTPFailure(statusCode: Int, url: URL, isMainFrame: Bool) {
        guard statusCode >= 400 else {
            return
        }
        if isMainFrame == false {
            guard self.isLikelyExternalPlayerFrameURL(url) else {
                return
            }
        }
        let kind: VideoPlaybackProviderFailure.Kind
        switch statusCode {
        case 403, 503:
            kind = .blocked(statusCode: statusCode)
        case 404, 410:
            kind = .sourceInvalid(statusCode: statusCode)
        default:
            kind = .providerError(statusCode: statusCode)
        }
        self.reportProviderFailure(VideoPlaybackProviderFailure(kind: kind, url: url))
    }

    /// 中文注释：连接层失败（超时/DNS/重置）——被网络屏蔽的典型形态。
    func reportConnectionFailure(_ error: Error, fallbackURL: URL?) {
        let nsError: NSError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return
        }
        let unreachableCodes: Set<Int> = [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorSecureConnectionFailed
        ]
        guard unreachableCodes.contains(nsError.code) else {
            return
        }
        let failingURL: URL? = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
            ?? fallbackURL
        guard let failingURL else {
            return
        }
        self.reportProviderFailure(
            VideoPlaybackProviderFailure(kind: .unreachable, url: failingURL)
        )
    }

    /// 中文注释：首个失败胜出——Cloudflare 拦截页自身的子资源可能继续产生
    /// 4xx，后续报告不得覆盖首因。
    private func reportProviderFailure(_ failure: VideoPlaybackProviderFailure) {
        guard self.providerFailure == nil else {
            return
        }
        self.providerFailure = failure
        #if DEBUG
        AppDebugLog.write(
            "[BrowseCraftVideoWebPlayer] provider-failure " +
            "kind=\(failure.kind) url=\(self.safeLogURL(failure.url))"
        )
        #endif
    }

    /// 中文注释：WKWebView 对被 CSP/X-Frame-Options 终止的子 frame（如
    /// Cloudflare 403 拦截页）不触发任何公开回调——kinogo/pelisplushd 实测。
    /// 因此主文档完成后，从页面提取外部播放器 URL，用同一 WebKit 栈的隐藏
    /// 探针 WebView 以主 frame 方式探测：主 frame 状态可靠可见，且指纹与
    /// 真实播放一致，不会产生 URLSession 式误报。
    func scheduleEmbedProbe(in webView: WKWebView) {
        guard self.providerFailure == nil, self.embedProbeCompletedURL != webView.url else {
            return
        }
        self.embedProbeTask?.cancel()
        let pageURL: URL? = webView.url
        self.embedProbeTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else {
                return
            }
            guard let candidateURL: URL = await self.firstExternalPlayerEmbedURL(in: webView) else {
                return
            }
            guard Task.isCancelled == false else {
                return
            }
            let failureKind: VideoPlaybackProviderFailure.Kind? =
                await VideoWebPlayerEmbedProbe(
                    configuration: self.configuration
                ).probe(url: candidateURL, referer: pageURL)
            guard Task.isCancelled == false, webView.url == pageURL else {
                return
            }
            self.embedProbeCompletedURL = pageURL
            if let failureKind {
                self.reportProviderFailure(
                    VideoPlaybackProviderFailure(kind: failureKind, url: candidateURL)
                )
            }
            #if DEBUG
            AppDebugLog.write(
                "[BrowseCraftVideoWebPlayer] embed-probe " +
                "url=\(self.safeLogURL(candidateURL)) " +
                "result=\(failureKind.map { String(describing: $0) } ?? "ok")"
            )
            #endif
        }
    }

    func cancelEmbedProbe() {
        self.embedProbeTask?.cancel()
        self.embedProbeTask = nil
    }

    /// 中文注释：候选来源与生成侧同一形状语义——`iframe[src]` 与非图像元素的
    /// `data-src` 携源；跨站、非噪声的第一个即外部播放器。
    private func firstExternalPlayerEmbedURL(in webView: WKWebView) async -> URL? {
        let script: String = #"""
        (() => {
          const urls = [];
          for (const frame of document.querySelectorAll("iframe[src]")) {
            urls.push(frame.src);
          }
          const skip = new Set(["IMG", "SOURCE", "VIDEO", "SCRIPT", "IFRAME", "LINK"]);
          for (const element of document.querySelectorAll("[data-src]")) {
            if (skip.has(element.tagName)) continue;
            const value = String(element.getAttribute("data-src") || "");
            if (/^https?:\/\//i.test(value)) urls.push(value);
          }
          return urls.slice(0, 12);
        })();
        """#
        guard let value: Any = try? await webView.evaluateJavaScript(script),
              let rawURLs: [Any] = value as? [Any] else {
            return nil
        }
        for rawURL: Any in rawURLs {
            guard let urlString: String = rawURL as? String,
                  let url: URL = URL(string: urlString),
                  let scheme: String = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  self.isLikelyExternalPlayerFrameURL(url) else {
                continue
            }
            return url
        }
        return nil
    }

    /// 中文注释：跨站（相对播放页主域）且未被噪声过滤丢弃的子 frame 文档
    /// 才视为外部播放器。embed 聚合器几乎总是跨站；广告 iframe 由噪声过滤排除。
    private func isLikelyExternalPlayerFrameURL(_ url: URL) -> Bool {
        guard let host: String = url.host?.lowercased() else {
            return false
        }
        if let initialHost: String = self.initialHost {
            let isSameSiteFamily: Bool = host == initialHost
                || host.hasSuffix(".\(initialHost)")
                || initialHost.hasSuffix(".\(host)")
            if isSameSiteFamily {
                return false
            }
        }
        return self.shouldBlockLikelyNoiseNavigation(url) == false
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

/// 中文注释：外部播放源失败的类型化状态。403/503 是"源站防护拦截当前出口"，
/// 连接层失败是"疑似网络屏蔽"，404/410 是片源失效——三者的用户动作不同，
/// 文案必须区分，不得合并成一句"加载失败"。
struct VideoPlaybackProviderFailure: Equatable {
    enum Kind: Equatable {
        case blocked(statusCode: Int)
        case unreachable
        case sourceInvalid(statusCode: Int)
        case providerError(statusCode: Int)
    }

    var kind: Kind
    var url: URL

    var host: String {
        return self.url.host ?? NSLocalizedString("video_player_provider_unknown_host", comment: "")
    }

    var title: String {
        switch self.kind {
        case .blocked, .unreachable:
            return NSLocalizedString("video_player_provider_title_unreachable", comment: "")
        case .sourceInvalid:
            return NSLocalizedString("video_player_provider_title_source_invalid", comment: "")
        case .providerError:
            return NSLocalizedString("video_player_provider_title_error", comment: "")
        }
    }

    var message: String {
        switch self.kind {
        case .blocked(let statusCode):
            return String(
                format: NSLocalizedString("video_player_provider_message_blocked", comment: ""),
                self.host,
                statusCode
            )
        case .unreachable:
            return String(
                format: NSLocalizedString("video_player_provider_message_unreachable", comment: ""),
                self.host
            )
        case .sourceInvalid(let statusCode):
            return String(
                format: NSLocalizedString("video_player_provider_message_source_invalid", comment: ""),
                self.host,
                statusCode
            )
        case .providerError(let statusCode):
            return String(
                format: NSLocalizedString("video_player_provider_message_provider_error", comment: ""),
                self.host,
                statusCode
            )
        }
    }

    var hint: String? {
        switch self.kind {
        case .blocked, .unreachable:
            return NSLocalizedString("video_player_provider_hint_change_network", comment: "")
        case .sourceInvalid:
            return NSLocalizedString("video_player_provider_hint_pick_another_source", comment: "")
        case .providerError:
            return nil
        }
    }
}

/// 中文注释：隐藏探针 WebView——以主 frame 方式加载外部播放器 URL，
/// 读取其 HTTP 状态或连接失败。与播放 WebView 同一 configuration
/// （同 Cookie store、同 UA 指纹），判决与真实播放一致。
@MainActor
private final class VideoWebPlayerEmbedProbe: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var continuation: CheckedContinuation<VideoPlaybackProviderFailure.Kind?, Never>?

    init(configuration: WKWebViewConfiguration) {
        self.webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1, height: 1),
            configuration: configuration
        )
        super.init()
        self.webView.navigationDelegate = self
    }

    func probe(url: URL, referer: URL?) async -> VideoPlaybackProviderFailure.Kind? {
        var request: URLRequest = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 12
        )
        if let referer: URL {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.webView.load(request)
        }
    }

    private func finish(_ kind: VideoPlaybackProviderFailure.Kind?) {
        guard let continuation = self.continuation else {
            return
        }
        self.continuation = nil
        self.webView.stopLoading()
        continuation.resume(returning: kind)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        guard navigationResponse.isForMainFrame,
              let httpResponse: HTTPURLResponse = navigationResponse.response as? HTTPURLResponse else {
            return .allow
        }
        switch httpResponse.statusCode {
        case ..<400:
            self.finish(nil)
        case 403, 503:
            self.finish(.blocked(statusCode: httpResponse.statusCode))
        case 404, 410:
            self.finish(.sourceInvalid(statusCode: httpResponse.statusCode))
        default:
            self.finish(.providerError(statusCode: httpResponse.statusCode))
        }
        return .cancel
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        let nsError: NSError = error as NSError
        guard nsError.domain == NSURLErrorDomain, nsError.code != NSURLErrorCancelled else {
            self.finish(nil)
            return
        }
        self.finish(.unreachable)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        self.finish(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        self.finish(nil)
    }
}
