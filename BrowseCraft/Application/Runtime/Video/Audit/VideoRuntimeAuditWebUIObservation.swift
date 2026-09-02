import Foundation
import WebKit
import BrowseCraftCore

// 中文注释：BC-EVIDENCE-077（批次 4）——WebUI 路线的前台观察点。
// 这里只定义观察端口、playing 事件、纯归约器与仅在 audit 模式注入的观察脚本；
// 前台承载由 UI 层用现有 VideoWebPlayerView 完成，不新建第二个 WebView 栈。

/// 中文注释：一次 `playing` 事件——元素身份 = 帧内随机 id + 元素序号；currentSrc 只留内存。
struct VideoRuntimeAuditMediaPlayingEvent: Hashable, Sendable {
    let elementID: String
    let currentSrc: String
}

struct VideoRuntimeAuditWebUIObservation: Hashable, Sendable {
    let playerStarted: Bool
    let bindingStatus: VideoRuntimeEvidenceMediaBindingStatus
    let mediaURL: URL?
    let timedOut: Bool
}

/// 中文注释：audit 驱动器请求前台观察的唯一端口；无实现（headless）时行为与批次 3 相同。
protocol VideoRuntimeAuditWebUIObserving: AnyObject, Sendable {
    @MainActor
    func observe(
        reference: SourceVideoPlaybackReference,
        requestConfig: SourcePlaybackRequestConfig?,
        sessionToken: String,
        timeout: TimeInterval
    ) async -> VideoRuntimeAuditWebUIObservation
}

/// 中文注释：BC-EVIDENCE-021 的操作化，纯函数、可单测：
/// 恰好一个元素 playing 且 currentSrc 为 http(s) → unique；
/// currentSrc 为 blob:/data:/空 → missing；≥2 个不同源的元素 playing → ambiguous。
enum VideoRuntimeAuditWebUIBindingReducer {
    static func reduce(
        events: [VideoRuntimeAuditMediaPlayingEvent],
        timedOut: Bool
    ) -> VideoRuntimeAuditWebUIObservation {
        guard events.isEmpty == false else {
            return VideoRuntimeAuditWebUIObservation(
                playerStarted: false,
                bindingStatus: .missing,
                mediaURL: nil,
                timedOut: timedOut
            )
        }
        var sourceByElement: [String: String] = [:]
        for event: VideoRuntimeAuditMediaPlayingEvent in events {
            sourceByElement[event.elementID] = event.currentSrc
        }
        let distinctSources: Set<String> = Set(sourceByElement.values)
        guard distinctSources.count == 1,
              let source: String = distinctSources.first else {
            return VideoRuntimeAuditWebUIObservation(
                playerStarted: true,
                bindingStatus: .ambiguous,
                mediaURL: nil,
                timedOut: timedOut
            )
        }
        guard let mediaURL: URL = Self.httpURL(source) else {
            return VideoRuntimeAuditWebUIObservation(
                playerStarted: true,
                bindingStatus: .missing,
                mediaURL: nil,
                timedOut: timedOut
            )
        }
        return VideoRuntimeAuditWebUIObservation(
            playerStarted: true,
            bindingStatus: .unique,
            mediaURL: mediaURL,
            timedOut: timedOut
        )
    }

    private static func httpURL(_ raw: String) -> URL? {
        guard let url: URL = URL(string: raw),
              let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

/// 中文注释：只在 audit 模式挂到 WKUserContentController 的 playing 观察者。
/// 脚本在 document start 注入全部 frame，捕获阶段监听 HTMLMediaElement 的 playing；
/// 上报只含 session token、元素 id 与 currentSrc，不含页面内容。
@MainActor
final class VideoRuntimeAuditMediaEventHandler: NSObject, WKScriptMessageHandler {
    static let messageName: String = "brgAuditMedia"

    let sessionToken: String
    private(set) var events: [VideoRuntimeAuditMediaPlayingEvent] = []
    private var firstEventContinuation: CheckedContinuation<Void, Never>?
    private weak var attachedController: WKUserContentController?

    init(sessionToken: String) {
        self.sessionToken = sessionToken
        super.init()
    }

    var userScript: WKUserScript {
        return WKUserScript(
            source: Self.script(sessionToken: self.sessionToken),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    func attach(to controller: WKUserContentController) {
        controller.addUserScript(self.userScript)
        controller.add(self, name: Self.messageName)
        self.attachedController = controller
    }

    func detach() {
        self.attachedController?.removeScriptMessageHandler(forName: Self.messageName)
        self.attachedController = nil
        self.resumeFirstEventWaiter()
    }

    /// 中文注释：等待首个 playing 事件；返回是否超时。超时或取消都不会让 continuation 悬挂。
    func waitForFirstPlaying(timeout: TimeInterval) async -> Bool {
        if self.events.isEmpty == false {
            return false
        }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                await self.firstEvent()
                return self.events.isEmpty
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                return true
            }
            let timedOut: Bool = await group.next() ?? true
            group.cancelAll()
            return timedOut
        }
    }

    private func firstEvent() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if self.events.isEmpty == false {
                    continuation.resume()
                } else {
                    self.firstEventContinuation = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.resumeFirstEventWaiter()
            }
        }
    }

    private func resumeFirstEventWaiter() {
        guard let continuation: CheckedContinuation<Void, Never> = self.firstEventContinuation else {
            return
        }
        self.firstEventContinuation = nil
        continuation.resume()
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageName,
              let body: [String: Any] = message.body as? [String: Any],
              let token: String = body["token"] as? String,
              let elementID: String = body["elementID"] as? String,
              let currentSrc: String = body["currentSrc"] as? String else {
            return
        }
        Task { @MainActor in
            guard token == self.sessionToken else {
                return
            }
            self.events.append(
                VideoRuntimeAuditMediaPlayingEvent(
                    elementID: elementID,
                    currentSrc: currentSrc
                )
            )
            self.resumeFirstEventWaiter()
        }
    }

    private static func script(sessionToken: String) -> String {
        let tokenLiteral: String = sessionToken
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "\"", with: "")
        return """
        (() => {
          if (window.__brgAuditMediaInstalled) { return; }
          window.__brgAuditMediaInstalled = true;
          const token = "\(tokenLiteral)";
          const frameID = Math.random().toString(36).slice(2, 10);
          const ordinals = new WeakMap();
          let nextOrdinal = 0;
          document.addEventListener("playing", (event) => {
            const target = event.target;
            if (!target || typeof HTMLMediaElement === "undefined" || !(target instanceof HTMLMediaElement)) { return; }
            if (!ordinals.has(target)) { nextOrdinal += 1; ordinals.set(target, nextOrdinal); }
            try {
              window.webkit.messageHandlers.\(Self.messageName).postMessage({
                token: token,
                elementID: frameID + ":" + ordinals.get(target),
                currentSrc: String(target.currentSrc || target.src || "")
              });
            } catch (error) {}
          }, true);
        })();
        """
    }
}
