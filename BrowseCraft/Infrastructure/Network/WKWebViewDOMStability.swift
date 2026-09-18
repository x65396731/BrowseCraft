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

    /// 中文注释：调用方在 `PageLoadRequest.readinessSelector` 上声明了选择器时的提前返回条件。
    /// 它只是**加速**条件：选择器有命中且连续若干次数量不变即返回；始终不命中则退回 `mechanism` 的判定，
    /// 因此不会比不声明更慢。数量稳定而不是「首次命中」，是为了让分批追加的列表把这一批追加完。
    struct SelectorReadiness: Sendable, Equatable {
        /// 中文注释：首次命中之后还需连续多少次数量不变。1 表示两次连续采样相等即可（约一个 checkInterval）。
        var requiredConsecutiveStableChecks: Int

        static let `default`: SelectorReadiness = SelectorReadiness(requiredConsecutiveStableChecks: 1)
    }

    enum Mechanism: Sendable, Equatable {
        case renderedLengthPolling(RenderedLengthPolling)
    }

    var mechanism: Mechanism
    var selectorReadiness: SelectorReadiness

    /// 中文注释：闸门基线——历史机制、历史取值。2026-09-18 的固定输入测量（见
    /// `WKWebViewDOMStabilityMeasurementTests`）表明这组取值不该被当成冗余削减，理由记在
    /// `minimumObservationChecks` 上。装配点必须显式声明本项，改动它是一次可复核的改动，
    /// 不是翻转一个隐藏默认值。
    static let baseline: WKWebViewDOMStabilityPolicy = WKWebViewDOMStabilityPolicy(
        mechanism: .renderedLengthPolling(.baseline),
        selectorReadiness: .default
    )
}

/// 中文注释：按声明的策略等待 DOM 稳定。返回实际等待时长与结束原因，便于测量与日志，不参与业务判断。
@MainActor
struct WKWebViewDOMStabilityWaiter {
    struct Outcome: Sendable, Equatable {
        /// 中文注释：`quiet` 表示真的安静下来了；另两个是保护性上限，说明页面在持续变更。
        enum Reason: String, Sendable {
            /// 中文注释：调用方声明的就绪选择器有命中且数量已稳定。
            case selectorReady
            case quiet
            case exhaustedChecks
        }

        var reason: Reason
        var waited: Duration
        var observedChecks: Int
        /// 中文注释：返回时就绪选择器的命中数；未声明选择器时为 nil，选择器非法时为 -1。
        var matchedCount: Int? = nil
    }

    let policy: WKWebViewDOMStabilityPolicy
    /// 中文注释：只用于把 JavaScript 结果异常归因到具体页面，与既有错误类型保持一致。
    let url: URL

    func waitForStableDOM(in webView: WKWebView, readinessSelector: String? = nil) async throws -> Outcome {
        switch self.policy.mechanism {
        case .renderedLengthPolling(let configuration):
            if let readinessSelector, readinessSelector.isEmpty == false {
                return try await self.waitForSelectorReadinessOrPolling(
                    selector: readinessSelector,
                    readiness: self.policy.selectorReadiness,
                    polling: configuration,
                    in: webView
                )
            }
            return try await self.waitByPollingRenderedLength(configuration, in: webView)
        }
    }

    // MARK: - 就绪选择器（加速条件）+ 历史机制（兜底）

    /// 中文注释：同一个循环里同时评估两个条件：选择器命中且数量稳定 → 提前返回；否则沿用历史机制的长度判定。
    /// 历史机制的每一步（观察下限、连续稳定次数、最大轮数、间隔）在这里逐字保留，所以声明选择器只可能更早返回，
    /// 不可能更晚。计时留在 Swift 侧——离屏 WebView 会节流页面内定时器（F2-7 实测）。
    private func waitForSelectorReadinessOrPolling(
        selector: String,
        readiness: WKWebViewDOMStabilityPolicy.SelectorReadiness,
        polling: WKWebViewDOMStabilityPolicy.RenderedLengthPolling,
        in webView: WKWebView
    ) async throws -> Outcome {
        let start: ContinuousClock.Instant = ContinuousClock.now
        var previousLength: Int?
        var consecutiveStableLengthChecks: Int = 0
        var previousCount: Int?
        var consecutiveStableCountChecks: Int = 0

        for checkIndex in 0..<polling.maximumChecks {
            let sample: ReadinessSample = try await self.readinessSample(selector: selector, in: webView)
            let observedCheckCount: Int = checkIndex + 1

            if sample.count > 0 {
                if let previousCount: Int, previousCount == sample.count {
                    consecutiveStableCountChecks += 1
                } else {
                    consecutiveStableCountChecks = 0
                }
                if consecutiveStableCountChecks >= readiness.requiredConsecutiveStableChecks {
                    return Outcome(
                        reason: .selectorReady,
                        waited: ContinuousClock.now - start,
                        observedChecks: observedCheckCount,
                        matchedCount: sample.count
                    )
                }
            } else {
                consecutiveStableCountChecks = 0
            }
            previousCount = sample.count

            if let previousLength: Int,
               abs(sample.length - previousLength) <= polling.stableLengthDelta {
                consecutiveStableLengthChecks += 1
            } else {
                consecutiveStableLengthChecks = 0
            }
            previousLength = sample.length

            if observedCheckCount >= polling.minimumObservationChecks,
               consecutiveStableLengthChecks >= polling.requiredConsecutiveStableChecks {
                return Outcome(
                    reason: .quiet,
                    waited: ContinuousClock.now - start,
                    observedChecks: observedCheckCount,
                    matchedCount: sample.count
                )
            }

            if observedCheckCount < polling.maximumChecks {
                try await Task.sleep(for: polling.checkInterval)
            }
        }

        return Outcome(
            reason: .exhaustedChecks,
            waited: ContinuousClock.now - start,
            observedChecks: polling.maximumChecks,
            matchedCount: previousCount
        )
    }

    private struct ReadinessSample {
        let count: Int
        let length: Int
    }

    /// 中文注释：一次往返同时取「选择器命中数」与「整页长度」。选择器非法时命中数记 -1（按未命中处理，退回历史判定），
    /// 不让一个坏选择器把整次加载变成错误。选择器经 JSON 编码注入，不拼接进脚本文本。
    private func readinessSample(selector: String, in webView: WKWebView) async throws -> ReadinessSample {
        let encodedSelector: String = try Self.jsonStringLiteral(selector)
        let result: Any? = try await webView.evaluateJavaScript(
            """
            (() => {
              let count = -1;
              try { count = document.querySelectorAll(\(encodedSelector)).length; } catch (error) { count = -1; }
              return { count: count, length: document.documentElement.outerHTML.length };
            })();
            """
        )
        guard let payload: [String: Any] = result as? [String: Any] else {
            throw WKWebViewHTMLLoaderError.unexpectedJavaScriptResult(url: self.url)
        }
        return ReadinessSample(
            count: Self.intValue(payload["count"]) ?? -1,
            length: Self.intValue(payload["length"]) ?? 0
        )
    }

    private static func jsonStringLiteral(_ value: String) throws -> String {
        let data: Data = try JSONSerialization.data(withJSONObject: [value])
        guard let array: String = String(data: data, encoding: .utf8),
              array.hasPrefix("["), array.hasSuffix("]") else {
            throw CocoaError(.coderInvalidValue)
        }
        return String(array.dropFirst().dropLast())
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int: Int = value as? Int {
            return int
        }
        if let double: Double = value as? Double {
            return Int(double)
        }
        return nil
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
