import BrowseCraftDomain
import BrowseCraftLog
import Foundation

enum AppBootstrapState {
    case loading
    case ready(AppContainer)
    case failed(AppBootstrapFailure)

    @MainActor
    static func bootstrap(
        loader: AppBootstrapLoader = AppBootstrapLoader()
    ) async -> AppBootstrapState {
        // 中文注释：启动公共钩子（BCA-OBS-014）：每一步记耗时，失败在 failedState 里记。
        let clock: ContinuousClock = ContinuousClock()
        let startedAt: ContinuousClock.Instant = clock.now
        AppLog.info(.startup, "bootstrap-started")

        // 中文注释：分两步捕获，只为埋点知道失败在哪一步（打开数据库与身份引导 / 组装容器）。
        let dependencies: AppBootstrapDependencies
        do {
            dependencies = try await loader.load()
        } catch {
            return Self.failedState(error, stage: .database)
        }
        AppLog.info(.startup, "bootstrap-dependencies-loaded", ["ms": .duration(clock.now - startedAt)])
        do {
            let container: AppContainer = try AppContainer(bootstrap: dependencies)
            AppLog.notice(.startup, "bootstrap-finished", ["ms": .duration(clock.now - startedAt)])
            return .ready(container)
        } catch {
            return Self.failedState(error, stage: .container)
        }
    }

    @MainActor
    private static func failedState(_ error: any Error, stage: BootstrapFailureStage) -> AppBootstrapState {
        let failure: AppBootstrapFailure = AppBootstrapFailure(error: error)
        // 中文注释：诊断码对用户是稳定的引用，但它只由类型名哈希而来；真正的原因必须同时落日志，
        // 否则拿到一个 BOOT-XXXX 也只能靠反推哈希去猜是哪个错误。
        AppLog.error(.startup, "bootstrap-failed", [
            "stage": .enumValue(stage),
            "diagnosticCode": .code(failure.diagnosticCode),
            "error": .error(error)
        ])
        AppAnalytics.shared.logAppBootstrapFailed(stage: stage)
        CrashDiagnostics.shared.recordBootstrapFailure(error: error, stage: stage)
        return .failed(failure)
    }
}

struct AppBootstrapFailure: Equatable {
    let diagnosticCode: String
    /// 中文注释：可安全外泄的错误摘要（类型名、domain:code，以及错误自己声明的状态码）。
    /// 与日志内容一致，失败页可整段复制给支持人员；不含凭据、密钥、地址或用户内容。
    let diagnosticDetail: String
    let title: String
    let message: String
    let recoverySuggestion: String

    init(error: any Error) {
        self.diagnosticCode = Self.diagnosticCode(for: error)
        self.diagnosticDetail = ErrorDiagnostics.summary(for: error)
        self.title = NSLocalizedString("bootstrap_failure_title", comment: "启动失败标题")
        self.message = NSLocalizedString("bootstrap_failure_message", comment: "启动失败说明")
        self.recoverySuggestion = NSLocalizedString("bootstrap_failure_recovery", comment: "启动失败的下一步")
    }

    /// 中文注释：交给支持人员的整段内容，与 `bootstrap-failed` 日志一致。
    var copyableDiagnostics: String {
        return "\(self.diagnosticCode)\n\(self.diagnosticDetail)"
    }

    private static func diagnosticCode(for error: any Error) -> String {
        let typeName: String = String(reflecting: type(of: error))
        let stableValue: UInt64 = typeName.utf8.reduce(1_469_598_103_934_665_603) { partial, byte in
            return (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return "BOOT-\(String(stableValue, radix: 16, uppercase: true))"
    }
}
