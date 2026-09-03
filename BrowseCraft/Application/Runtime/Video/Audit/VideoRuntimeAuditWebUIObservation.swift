// 中文注释：显式 runtime audit 只随 Debug 构建编译；Release/TestFlight 不含审计代码。
#if DEBUG
import Foundation
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
#endif
