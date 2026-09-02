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

/// 中文注释：`BC-EVIDENCE-078.5`（09-03 修订）——激活循环的可观察事实，由注入脚本逐轮上报：
/// 观察窗内出现过多少个带 http(s) 源的媒体元素、对它们调用了几次 `play()`、携源元素是否滚入。
/// 只用于把「播放器根本没露出媒体元素」与「元素出现、按合同激活过但始终没开始播」分开；
/// 不解释站点意图，不构成 playerStarted。
struct VideoRuntimeAuditActivationSnapshot: Hashable, Sendable {
    let candidateElementCount: Int
    let playAttemptCount: Int
    let carrierScrolled: Bool

    static let none: VideoRuntimeAuditActivationSnapshot = VideoRuntimeAuditActivationSnapshot(
        candidateElementCount: 0,
        playAttemptCount: 0,
        carrierScrolled: false
    )

    func merging(_ other: VideoRuntimeAuditActivationSnapshot) -> VideoRuntimeAuditActivationSnapshot {
        return VideoRuntimeAuditActivationSnapshot(
            candidateElementCount: max(self.candidateElementCount, other.candidateElementCount),
            playAttemptCount: max(self.playAttemptCount, other.playAttemptCount),
            carrierScrolled: self.carrierScrolled || other.carrierScrolled
        )
    }
}

struct VideoRuntimeAuditWebUIObservation: Hashable, Sendable {
    let playerStarted: Bool
    let bindingStatus: VideoRuntimeEvidenceMediaBindingStatus
    let mediaURL: URL?
    let timedOut: Bool
    let activation: VideoRuntimeAuditActivationSnapshot

    /// 中文注释：binding `missing` 时的 typed 原因码——唯一定义点（`BC-EVIDENCE-078.5`）。
    /// - 窗口内已按 078.2 对带源媒体元素调用过 `play()` 仍无 `playing` → `player-activation-not-started`
    ///   （已做完合同允许的全部激活，播放器仍未开始；常见于需人工点击 / 反自动化门控的第三方嵌入播放器）；
    /// - 窗口内没有任何带源媒体元素可激活 → `player-session-timeout`；
    /// - 未超时但无最终媒体观察点 → `final-media-observation-unavailable`。
    var missingBindingRejectionReason: String {
        guard self.timedOut else {
            return "final-media-observation-unavailable"
        }
        return self.activation.playAttemptCount > 0
            ? "player-activation-not-started"
            : "player-session-timeout"
    }
}

/// 中文注释：audit 驱动器请求前台观察的唯一端口；无实现（headless）时行为与批次 3 相同。
protocol VideoRuntimeAuditWebUIObserving: AnyObject, Sendable {
    /// - Parameter activationSelector: `BC-EVIDENCE-078.1`——catalog 已声明的携源元素 CSS 选择器；
    ///   nil 表示不做滚入视口激活。
    @MainActor
    func observe(
        reference: SourceVideoPlaybackReference,
        requestConfig: SourcePlaybackRequestConfig?,
        sessionToken: String,
        timeout: TimeInterval,
        activationSelector: String?
    ) async -> VideoRuntimeAuditWebUIObservation
}

/// 中文注释：`BC-EVIDENCE-078.1` 的选择器来源——只取 catalog 声明的 css 选择器，其它 selectorKind
/// 或空选择器不激活。纯函数、可单测。
enum VideoRuntimeAuditActivationSelector {
    static func cssSelector(selector: String?, selectorKind: String?) -> String? {
        guard let selector: String = selector?.trimmingCharacters(in: .whitespacesAndNewlines),
              selector.isEmpty == false else {
            return nil
        }
        if let selectorKind: String, selectorKind.lowercased() != "css" {
            return nil
        }
        return selector
    }
}

/// 中文注释：BC-EVIDENCE-021 的操作化，纯函数、可单测。
/// - `data:` 源没有网络请求，按定义不可能是「最终播放媒体请求」（播放器解锁自动播放/
///   探测拦截用的内联假视频），不参与绑定，只贡献 playerStarted；
/// - 其余源中恰好一个元素 playing 且 currentSrc 为 http(s) → unique；
///   `blob:`/空（MSE、不可观察）→ missing；≥2 个不同源 → ambiguous。
enum VideoRuntimeAuditWebUIBindingReducer {
    static func reduce(
        events: [VideoRuntimeAuditMediaPlayingEvent],
        timedOut: Bool,
        activation: VideoRuntimeAuditActivationSnapshot = .none
    ) -> VideoRuntimeAuditWebUIObservation {
        let playerStarted: Bool = events.isEmpty == false
        var sourceByElement: [String: String] = [:]
        for event: VideoRuntimeAuditMediaPlayingEvent in events
        where Self.isBindingCandidate(event.currentSrc) {
            sourceByElement[event.elementID] = event.currentSrc
        }
        let distinctSources: Set<String> = Set(sourceByElement.values)
        guard distinctSources.isEmpty == false else {
            return VideoRuntimeAuditWebUIObservation(
                playerStarted: playerStarted,
                bindingStatus: .missing,
                mediaURL: nil,
                timedOut: timedOut,
                activation: activation
            )
        }
        guard distinctSources.count == 1,
              let source: String = distinctSources.first else {
            return VideoRuntimeAuditWebUIObservation(
                playerStarted: true,
                bindingStatus: .ambiguous,
                mediaURL: nil,
                timedOut: timedOut,
                activation: activation
            )
        }
        guard let mediaURL: URL = Self.httpURL(source) else {
            return VideoRuntimeAuditWebUIObservation(
                playerStarted: true,
                bindingStatus: .missing,
                mediaURL: nil,
                timedOut: timedOut,
                activation: activation
            )
        }
        return VideoRuntimeAuditWebUIObservation(
            playerStarted: true,
            bindingStatus: .unique,
            mediaURL: mediaURL,
            timedOut: timedOut,
            activation: activation
        )
    }

    /// 中文注释：非空且不是 `data:` 的源才是绑定候选（http(s) 可 unique，blob: 只能 missing）。
    static func isBindingCandidate(_ raw: String) -> Bool {
        let trimmed: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return false
        }
        return trimmed.lowercased().hasPrefix("data:") == false
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
/// 脚本在 document start 注入全部 frame，用 MutationObserver + 轮询发现媒体元素并把
/// `playing` 监听**直接挂在元素上**（实测 WebKit 上 document/window 级捕获收不到媒体事件）；
/// 上报只含 session token、元素 id 与 currentSrc，不含页面内容。
@MainActor
final class VideoRuntimeAuditMediaEventHandler: NSObject, WKScriptMessageHandler {
    static let messageName: String = "brgAuditMedia"

    let sessionToken: String
    /// 中文注释：`BC-EVIDENCE-078.1` 携源元素选择器；nil 不做滚入视口。
    let activationSelector: String?
    private(set) var events: [VideoRuntimeAuditMediaPlayingEvent] = []
    /// 中文注释：`BC-EVIDENCE-078.5`——激活循环上报的事实，按轮取最大值合并。
    private(set) var activation: VideoRuntimeAuditActivationSnapshot = .none
    private var candidateContinuation: CheckedContinuation<Void, Never>?
    private weak var attachedController: WKUserContentController?

    init(sessionToken: String, activationSelector: String? = nil) {
        self.sessionToken = sessionToken
        self.activationSelector = activationSelector
        super.init()
    }

    var userScript: WKUserScript {
        return WKUserScript(
            source: Self.script(
                sessionToken: self.sessionToken,
                activationSelector: self.activationSelector
            ),
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
        self.resumeCandidateWaiter()
    }

    private var hasBindingCandidateEvent: Bool {
        return self.events.contains { event in
            VideoRuntimeAuditWebUIBindingReducer.isBindingCandidate(event.currentSrc)
        }
    }

    /// 中文注释：等待首个**绑定候选**（非 data: 源）元素的 playing；返回是否超时。
    /// 假视频的 playing 只记 playerStarted，不结束等待。超时或取消都不会让 continuation 悬挂。
    func waitForFirstBindingCandidatePlaying(timeout: TimeInterval) async -> Bool {
        if self.hasBindingCandidateEvent {
            return false
        }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                await self.firstCandidateEvent()
                return self.hasBindingCandidateEvent == false
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

    private func firstCandidateEvent() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if self.hasBindingCandidateEvent {
                    continuation.resume()
                } else {
                    self.candidateContinuation = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.resumeCandidateWaiter()
            }
        }
    }

    private func resumeCandidateWaiter() {
        guard let continuation: CheckedContinuation<Void, Never> = self.candidateContinuation else {
            return
        }
        self.candidateContinuation = nil
        continuation.resume()
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageName,
              let body: [String: Any] = message.body as? [String: Any],
              let token: String = body["token"] as? String else {
            return
        }
        if body["kind"] as? String == "activation" {
            let snapshot: VideoRuntimeAuditActivationSnapshot = VideoRuntimeAuditActivationSnapshot(
                candidateElementCount: max(0, (body["candidates"] as? Int) ?? 0),
                playAttemptCount: max(0, (body["playAttempts"] as? Int) ?? 0),
                carrierScrolled: (body["scrolled"] as? Bool) ?? false
            )
            Task { @MainActor in
                guard token == self.sessionToken else {
                    return
                }
                self.activation = self.activation.merging(snapshot)
            }
            return
        }
        guard let elementID: String = body["elementID"] as? String,
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
            if VideoRuntimeAuditWebUIBindingReducer.isBindingCandidate(currentSrc) {
                self.resumeCandidateWaiter()
            }
        }
    }

    /// 中文注释：`BC-EVIDENCE-078.2` 的界限——每元素最多 2 次 `play()`、间隔 ≥1 秒、总循环有界。
    static let maximumPlayAttemptsPerElement: Int = 2
    static let activationLoopIterations: Int = 30

    private static func script(sessionToken: String, activationSelector: String?) -> String {
        let tokenLiteral: String = sessionToken
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "\"", with: "")
        let selectorLiteral: String
        if let activationSelector: String,
           let data: Data = try? JSONSerialization.data(
               withJSONObject: activationSelector,
               options: [.fragmentsAllowed]
           ),
           let json: String = String(data: data, encoding: .utf8) {
            selectorLiteral = json
        } else {
            selectorLiteral = "null"
        }
        return """
        (() => {
          if (window.__brgAuditMediaInstalled) { return; }
          window.__brgAuditMediaInstalled = true;
          const token = "\(tokenLiteral)";
          const activationSelector = \(selectorLiteral);
          const maxPlayAttempts = \(Self.maximumPlayAttemptsPerElement);
          const maxLoops = \(Self.activationLoopIterations);
          const frameID = Math.random().toString(36).slice(2, 10);
          const ordinals = new WeakMap();
          const attached = new WeakSet();
          const playAttempts = new WeakMap();
          let loops = 0;
          let scrolled = false;
          let nextOrdinal = 0;
          const isCandidateSource = (element) => {
            const source = String(element.currentSrc || element.src || "").trim();
            return source.length > 0 && !/^data:/i.test(source);
          };
          // BC-EVIDENCE-078.1：声明携源元素滚入视口（一次）；078.2：绑定候选媒体元素 play()（每元素 ≤2 次）。
          let totalPlayAttempts = 0;
          const activate = () => {
            loops += 1;
            if (loops > maxLoops) { return; }
            if (!scrolled && activationSelector) {
              try {
                const carrier = document.querySelector(activationSelector);
                if (carrier) { scrolled = true; carrier.scrollIntoView({ block: "center" }); }
              } catch (error) {}
            }
            let candidates = 0;
            document.querySelectorAll("video, audio").forEach((element) => {
              if (!isCandidateSource(element)) { return; }
              candidates += 1;
              if (!element.paused) { return; }
              const attempts = playAttempts.get(element) || 0;
              if (attempts >= maxPlayAttempts) { return; }
              playAttempts.set(element, attempts + 1);
              totalPlayAttempts += 1;
              try { const result = element.play(); if (result && result.catch) { result.catch(() => {}); } } catch (error) {}
            });
            // BC-EVIDENCE-078.5：逐轮上报激活事实（不解释站点意图）。
            try {
              window.webkit.messageHandlers.\(Self.messageName).postMessage({
                token: token,
                kind: "activation",
                candidates: candidates,
                playAttempts: totalPlayAttempts,
                scrolled: scrolled
              });
            } catch (error) {}
          };
          const report = (element) => {
            if (!ordinals.has(element)) { nextOrdinal += 1; ordinals.set(element, nextOrdinal); }
            try {
              window.webkit.messageHandlers.\(Self.messageName).postMessage({
                token: token,
                kind: "playing",
                elementID: frameID + ":" + ordinals.get(element),
                currentSrc: String(element.currentSrc || element.src || "")
              });
            } catch (error) {}
          };
          const scan = () => {
            if (!document.querySelectorAll) { return; }
            document.querySelectorAll("video, audio").forEach((element) => {
              if (attached.has(element)) { return; }
              attached.add(element);
              element.addEventListener("playing", () => report(element));
              if (!element.paused && !element.ended && element.currentTime > 0) { report(element); }
            });
          };
          let scanPending = false;
          const scheduleScan = () => {
            if (scanPending) { return; }
            scanPending = true;
            setTimeout(() => { scanPending = false; scan(); }, 250);
          };
          scan();
          try { new MutationObserver(scheduleScan).observe(document, { childList: true, subtree: true }); } catch (error) {}
          setInterval(scan, 1000);
          setTimeout(activate, 1500);
          setInterval(activate, 1000);
        })();
        """
    }
}
