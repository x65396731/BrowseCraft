// 中文注释：只在 audit 模式挂到 WKUserContentController 的 playing 观察者（WebKit 适配器）。
// 端口、事件与归约器留在 Application/Runtime/Video/Audit；这里只做 WKScriptMessageHandler 桥接。
#if DEBUG
import Foundation
import WebKit

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

extension VideoRuntimeAuditMediaEventHandler: VideoWebPlayerUserContentAttaching {}
#endif
