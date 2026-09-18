import Foundation

// 中文注释：引导失败页此前只显示一个由「错误类型名」哈希出来的诊断码，底层原因不进任何日志。
// 2026-09-18 在模拟器上排查一次引导失败时，只能把代码库里所有错误类型名逐个哈希去反推才对上是哪个错误，
// 而它携带的 OSStatus（真正的原因）在任何地方都看不到。这里补上可安全记录的错误摘要。

/// 中文注释：错误自己声明「可以安全写进日志与诊断信息的摘要」。
///
/// 不实现本协议的错误只记类型名与 `NSError` 的 domain:code。之所以不直接 dump `String(describing:)`：
/// 任意错误的描述里可能带 Cookie、token、授权头、设备标识、密钥材料或用户路径，AGENTS.md 明确禁止记录。
/// 由错误类型自己声明摘要，等于把「什么可以外泄」这件事变成显式、可审阅的决定，而不是碰运气。
protocol DiagnosticSummaryProviding {
    /// 中文注释：只放定位问题必需的短信息（状态码、枚举分支名），不得包含凭据、密钥、地址或用户内容。
    var diagnosticSummary: String { get }
}

enum ErrorDiagnostics {
    /// 中文注释：类型名 + domain:code，错误若声明了摘要则再附上（摘要仍过一遍脱敏）。
    /// 输出既进 OSLog，也可由引导失败页复制给支持人员，因此两处内容一致、都不含敏感材料。
    static func summary(for error: any Error) -> String {
        var fields: [String] = [
            "type=\(String(reflecting: type(of: error)))",
            "code=\(AppLog.safeErrorCode(error))"
        ]
        if let diagnosable: any DiagnosticSummaryProviding = error as? any DiagnosticSummaryProviding {
            fields.append("detail=\(AppLog.sanitizedDebugMessage(diagnosable.diagnosticSummary))")
        }
        return fields.joined(separator: " ")
    }
}
