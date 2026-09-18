import BrowseCraftDomain
import Foundation

enum AppBootstrapState {
    case loading
    case ready(AppContainer)
    case failed(AppBootstrapFailure)

    @MainActor
    static func bootstrap(
        loader: AppBootstrapLoader = AppBootstrapLoader()
    ) async -> AppBootstrapState {
        // 中文注释：内核/runtime 的调试日志经 sink 汇入 App 既有的 AppDebugLog，
        // 让包内代码不必依赖 App 的日志分类。
        RuleRuntimeDebugLog.shared.install { record in
            guard let stage: RuleExecutionStage = record.stage else {
                AppDebugLog.write(record.fields["message"] ?? record.event)
                return
            }
            var metadata: [String: String] = record.fields
            metadata["stage"] = stage.rawValue
            AppLog.debug(.rule, event: record.event, metadata: metadata)
        }

        do {
            let dependencies: AppBootstrapDependencies = try await loader.load()
            return .ready(try AppContainer(bootstrap: dependencies))
        } catch {
            let failure: AppBootstrapFailure = AppBootstrapFailure(error: error)
            // 中文注释：诊断码对用户是稳定的引用，但它只由类型名哈希而来；真正的原因必须同时落日志，
            // 否则拿到一个 BOOT-XXXX 也只能靠反推哈希去猜是哪个错误。
            AppLog.error(
                .startup,
                event: "bootstrap-failed",
                metadata: [
                    "diagnosticCode": failure.diagnosticCode,
                    "diagnostics": failure.diagnosticDetail
                ]
            )
            return .failed(failure)
        }
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
        self.title = "BrowseCraft couldn’t start"
        self.message = "The app couldn’t open its local data safely. Your data was not deleted or reset."
        self.recoverySuggestion = "Quit and reopen the app. If the problem continues, include the diagnostic code when requesting support."
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
