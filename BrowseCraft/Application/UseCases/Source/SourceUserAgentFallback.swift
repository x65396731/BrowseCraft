import Foundation
import BrowseCraftDomain

/// 中文注释：`BCA-RUNTIME-010`（fwq `APP-MEMO-037`，设计稿第 54 节）——规则在桌面模板上匹配不到内容时，
/// 同一操作换手机 Safari UA 重做一次；成功就按来源记住，之后该来源的取页都带手机 UA。
///
/// 依据：站点按 UA 分桌面 / 手机两套模板，困难档云端取页不能指定 UA（官方 `/scrape` 只有
/// url / format / proxy / country / parse），挑战站被升到实体机浏览器、拿回手机模板，规则就按手机模板写成；
/// App 用规则里的桌面 UA 取到桌面模板，各层报「规则没有匹配到内容」（2026-10-13 huanmengacg 真机）。
/// 只认「匹配不到内容」：网络、状态码、挑战未过等错误不触发，不把换 UA 变成万能兜底（同 `BCA-RUNTIME-005`）。
final class SourceUserAgentFallback: @unchecked Sendable {
    static let shared: SourceUserAgentFallback = SourceUserAgentFallback(defaults: .standard)

    private enum State: String {
        /// 手机 UA 重做成功——该来源一律带手机 UA。
        case mobile
        /// 手机 UA 也匹配不到——不再重试，照旧用规则 UA。
        case mobileFailed
    }

    private static let defaultsKey: String = "BrowseCraft.sourceUserAgentFallback.v1"

    private let defaults: UserDefaults
    private let lock: NSLock = NSLock()
    /// 来源 id → (规则版本, 状态)；规则版本取 `Source.updatedAt`，规则更新后重新判。
    private var states: [String: (version: String, state: State)]
    /// 正在用手机 UA 重做的来源（重做期间这些来源的取页也带手机 UA）。
    private var trying: Set<String> = []

    init(defaults: UserDefaults) {
        self.defaults = defaults
        var loaded: [String: (version: String, state: State)] = [:]
        if let stored: [String: String] = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] {
            for (sourceID, value) in stored {
                let parts: [Substring] = value.split(separator: "|", maxSplits: 1)
                if parts.count == 2, let state: State = State(rawValue: String(parts[1])) {
                    loaded[sourceID] = (String(parts[0]), state)
                }
            }
        }
        self.states = loaded
    }

    /// 取页时要不要把 UA 换成手机 Safari（直接请求与 WebView 两条路共用）。
    func overridingUserAgent(forSourceID sourceID: String?) -> String? {
        guard let sourceID: String = sourceID else {
            return nil
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.trying.contains(sourceID) || self.states[sourceID]?.state == .mobile {
            return ClientUserAgent.mobileSafari
        }
        return nil
    }

    /// 在请求头上套用来源的 UA 选择；没有选择时原样返回。
    func applying(to headers: [String: String], sourceID: String?) -> [String: String] {
        guard let userAgent: String = self.overridingUserAgent(forSourceID: sourceID) else {
            return headers
        }
        var resolved: [String: String] = headers.filter { key, _ in
            key.caseInsensitiveCompare("User-Agent") != .orderedSame
        }
        resolved["User-Agent"] = userAgent
        return resolved
    }

    /// 跑一次运行时操作；以「匹配不到内容」失败（或 `isEmpty` 判为空）且该来源还没判过时，换手机 UA 重做一次。
    func perform<Output>(
        source: Source,
        isEmpty: (Output) -> Bool = { _ in false },
        isolation: isolated (any Actor)? = #isolation,
        _ operation: () async throws -> Output
    ) async throws -> Output {
        let version: String = Self.version(of: source)
        let decided: Bool = self.isDecided(sourceID: source.id, version: version)
        do {
            let output: Output = try await operation()
            guard decided == false, isEmpty(output) else {
                return output
            }
            return try await self.retryWithMobile(source: source, version: version, original: output, isolation: isolation, operation)
        } catch {
            guard decided == false, Self.isSelectorEmpty(error) else {
                throw error
            }
            do {
                return try await self.retryWithMobile(source: source, version: version, original: nil, isolation: isolation, operation, isEmpty: isEmpty)
            } catch SourceUserAgentFallbackError.mobileAlsoEmpty {
                throw error
            }
        }
    }

    private func retryWithMobile<Output>(
        source: Source,
        version: String,
        original: Output?,
        isolation: isolated (any Actor)? = #isolation,
        _ operation: () async throws -> Output,
        isEmpty: (Output) -> Bool = { _ in false }
    ) async throws -> Output {
        self.beginTrying(sourceID: source.id)
        #if DEBUG
        AppDebugLog.write("[BrowseCraftUserAgentFallback] retry with mobile UA source=\(source.id)")
        #endif
        let retried: Output
        do {
            retried = try await operation()
        } catch {
            self.finishTrying(sourceID: source.id, version: version, state: Self.isSelectorEmpty(error) ? .mobileFailed : nil)
            if Self.isSelectorEmpty(error) {
                if let original: Output = original {
                    return original
                }
                throw SourceUserAgentFallbackError.mobileAlsoEmpty
            }
            throw error
        }
        if isEmpty(retried) {
            self.finishTrying(sourceID: source.id, version: version, state: .mobileFailed)
            if let original: Output = original {
                return original
            }
            throw SourceUserAgentFallbackError.mobileAlsoEmpty
        }
        self.finishTrying(sourceID: source.id, version: version, state: .mobile)
        return retried
    }

    private func beginTrying(sourceID: String) {
        self.lock.lock()
        self.trying.insert(sourceID)
        self.lock.unlock()
    }

    private func finishTrying(sourceID: String, version: String, state: State?) {
        self.lock.lock()
        self.trying.remove(sourceID)
        if let state: State = state {
            self.states[sourceID] = (version, state)
        }
        let snapshot: [String: String] = self.states.mapValues { "\($0.version)|\($0.state.rawValue)" }
        self.lock.unlock()
        self.defaults.set(snapshot, forKey: Self.defaultsKey)
        #if DEBUG
        AppDebugLog.write("[BrowseCraftUserAgentFallback] decided source=\(sourceID) state=\(state?.rawValue ?? "undecided")")
        #endif
    }

    private func isDecided(sourceID: String, version: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let entry: (version: String, state: State) = self.states[sourceID] else {
            return false
        }
        if entry.version != version {
            // 中文注释：规则更新了——旧的判断作废，重新判。
            self.states[sourceID] = nil
            return false
        }
        return true
    }

    private static func version(of source: Source) -> String {
        return String(Int(source.updatedAt.timeIntervalSince1970))
    }

    private static func isSelectorEmpty(_ error: Error) -> Bool {
        if case .selectorEmpty = RuleExecutionErrorClassifier.classified(error) {
            return true
        }
        return false
    }
}

enum SourceUserAgentFallbackError: Error {
    /// 手机 UA 重做也匹配不到——调用方照旧抛原来的错误。
    case mobileAlsoEmpty
}
