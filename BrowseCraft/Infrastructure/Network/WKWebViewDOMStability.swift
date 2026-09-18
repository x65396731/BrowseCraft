import Foundation
import WebKit

// 中文注释：「渲染后的 DOM 何时算稳定」此前是 WKWebViewHTMLLoader 内部一组私有常量。它决定所有站点、
// 所有 kind 的 needsWebView 页面要额外等多久，改一个数字就会同时改变全部行为，而调用方看不出这层约定。
// 这里把它提成显式声明的策略值：装配点必须写明用哪套机制、取什么值。

/// 中文注释：DOM 稳定判定策略。`baseline` 逐字固化 2026-09-18 之前的取值，作为闸门基线。
struct WKWebViewDOMStabilityPolicy: Sendable, Equatable {
    /// 中文注释：轮询整页 `outerHTML.length`，长度连续若干轮波动不超过阈值即视为稳定。
    /// 这是历史上唯一的机制，两点代价：每轮都要在 WebContent 进程里序列化整棵 DOM；
    /// 且有「最少观察轮数」下限，页面早就安静也必须等满。
    struct RenderedLengthPolling: Sendable, Equatable {
        var checkInterval: Duration
        var maximumChecks: Int
        /// 中文注释：判定稳定之前必须观察满的轮数，与 `checkInterval` 一起形成约 1500ms 的固定下限。
        /// 这条下限是必需的，不是保守冗余：页面可能在 didFinish 之后先安静一段、再用定时器写入正文
        /// （固定输入测量 `lateContent`：正文 800ms 才出现）。只看「连续若干毫秒无变更」会在 300ms
        /// 就判定稳定并交出空正文。削减它等于放弃这条保护。
        var minimumObservationChecks: Int
        var requiredConsecutiveStableChecks: Int
        var stableLengthDelta: Int

        /// 中文注释：逐字等于历史取值。最小等待 = 6 次测量 + 5 × 300ms 睡眠；最坏 = 12 次测量 + 11 × 300ms。
        static let baseline: RenderedLengthPolling = RenderedLengthPolling(
            checkInterval: .milliseconds(300),
            maximumChecks: 12,
            minimumObservationChecks: 6,
            requiredConsecutiveStableChecks: 3,
            stableLengthDelta: 32
        )
    }

    enum Mechanism: Sendable, Equatable {
        case renderedLengthPolling(RenderedLengthPolling)
    }

    var mechanism: Mechanism

    /// 中文注释：闸门基线——历史机制、历史取值。2026-09-18 的固定输入测量（见
    /// `WKWebViewDOMStabilityMeasurementTests`）表明这组取值不该被当成冗余削减，理由记在
    /// `minimumObservationChecks` 上。装配点必须显式声明本项，改动它是一次可复核的改动，
    /// 不是翻转一个隐藏默认值。
    static let baseline: WKWebViewDOMStabilityPolicy = WKWebViewDOMStabilityPolicy(
        mechanism: .renderedLengthPolling(.baseline)
    )
}

/// 中文注释：按声明的策略等待 DOM 稳定。返回实际等待时长与结束原因，便于测量与日志，不参与业务判断。
@MainActor
struct WKWebViewDOMStabilityWaiter {
    struct Outcome: Sendable, Equatable {
        /// 中文注释：`quiet` 表示真的安静下来了；另两个是保护性上限，说明页面在持续变更。
        enum Reason: String, Sendable {
            case quiet
            case exhaustedChecks
        }

        var reason: Reason
        var waited: Duration
        var observedChecks: Int
    }

    let policy: WKWebViewDOMStabilityPolicy
    /// 中文注释：只用于把 JavaScript 结果异常归因到具体页面，与既有错误类型保持一致。
    let url: URL

    func waitForStableDOM(in webView: WKWebView) async throws -> Outcome {
        switch self.policy.mechanism {
        case .renderedLengthPolling(let configuration):
            return try await self.waitByPollingRenderedLength(configuration, in: webView)
        }
    }

    // MARK: - 历史机制

    private func waitByPollingRenderedLength(
        _ configuration: WKWebViewDOMStabilityPolicy.RenderedLengthPolling,
        in webView: WKWebView
    ) async throws -> Outcome {
        let start: ContinuousClock.Instant = ContinuousClock.now
        var previousLength: Int?
        var consecutiveStableChecks: Int = 0

        for checkIndex in 0..<configuration.maximumChecks {
            let currentLength: Int = try await self.renderedHTMLLength(in: webView)
            if let previousLength: Int,
               abs(currentLength - previousLength) <= configuration.stableLengthDelta {
                consecutiveStableChecks += 1
            } else {
                consecutiveStableChecks = 0
            }

            let observedCheckCount: Int = checkIndex + 1
            if observedCheckCount >= configuration.minimumObservationChecks,
               consecutiveStableChecks >= configuration.requiredConsecutiveStableChecks {
                return Outcome(
                    reason: .quiet,
                    waited: ContinuousClock.now - start,
                    observedChecks: observedCheckCount
                )
            }

            previousLength = currentLength
            if observedCheckCount < configuration.maximumChecks {
                try await Task.sleep(for: configuration.checkInterval)
            }
        }

        return Outcome(
            reason: .exhaustedChecks,
            waited: ContinuousClock.now - start,
            observedChecks: configuration.maximumChecks
        )
    }

    private func renderedHTMLLength(in webView: WKWebView) async throws -> Int {
        let result: Any? = try await webView.evaluateJavaScript(
            "document.documentElement.outerHTML.length"
        )

        if let length: Int = result as? Int {
            return length
        }

        if let length: Double = result as? Double {
            return Int(length)
        }

        throw WKWebViewHTMLLoaderError.unexpectedJavaScriptResult(url: self.url)
    }
}

extension Duration {
    /// 中文注释：只用于日志与测量输出，不参与判断。
    var milliseconds: Int {
        let components: (seconds: Int64, attoseconds: Int64) = self.components
        return Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
    }
}
