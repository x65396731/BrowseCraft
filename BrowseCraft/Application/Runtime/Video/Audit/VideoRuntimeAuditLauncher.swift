// 中文注释：显式 runtime audit 只随 Debug 构建编译；Release/TestFlight 不含审计代码。
#if DEBUG
import Foundation

// 中文注释：显式 runtime audit 的唯一入口（BC-EVIDENCE-076.2）：只有
// BRG_RUNTIME_AUDIT_CATALOG_PATH 与 BRG_RUNTIME_AUDIT_OUTPUT_PATH 同时存在才进入 audit
// session；缺任一时 App 行为与现状一致——不创建 recorder、不持久化、不导出。
// evidence 只写到输出路径，不进入数据库、Core 模型或播放引用。
struct VideoRuntimeAuditLaunchRequest {
    static let catalogPathEnvironmentKey: String = "BRG_RUNTIME_AUDIT_CATALOG_PATH"
    static let outputPathEnvironmentKey: String = "BRG_RUNTIME_AUDIT_OUTPUT_PATH"

    let catalogPath: String
    let outputPath: String

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> VideoRuntimeAuditLaunchRequest? {
        guard let catalogPath: String = environment[Self.catalogPathEnvironmentKey],
              catalogPath.isEmpty == false,
              let outputPath: String = environment[Self.outputPathEnvironmentKey],
              outputPath.isEmpty == false else {
            return nil
        }
        return VideoRuntimeAuditLaunchRequest(
            catalogPath: catalogPath,
            outputPath: outputPath
        )
    }
}

struct VideoRuntimeAuditLauncher {
    private let runtimeFactory: VideoSourceRuntimeFactory
    /// 中文注释：BC-EVIDENCE-077.1——前台 WebUI 观察端口由 composition root 注入；nil 即 headless。
    private let webUIObserver: (any VideoRuntimeAuditWebUIObserving)?
    /// 中文注释：BC-EVIDENCE-079.4——探针与播放器共用的请求头提供者。
    private let browserRequestHeaderProvider: (any BrowserRequestHeaderProviding)?

    init(
        runtimeFactory: VideoSourceRuntimeFactory,
        webUIObserver: (any VideoRuntimeAuditWebUIObserving)? = nil,
        browserRequestHeaderProvider: (any BrowserRequestHeaderProviding)? = nil
    ) {
        self.runtimeFactory = runtimeFactory
        self.webUIObserver = webUIObserver
        self.browserRequestHeaderProvider = browserRequestHeaderProvider
    }

    /// 中文注释：audit 结束（成功或失败）都写一份结果标记文件（`<outputPath>.status`），
    /// 驱动方（模拟器脚本）以它判断结束；失败时 evidence 文件不落盘。
    func runIfRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async {
        guard let request: VideoRuntimeAuditLaunchRequest = .fromEnvironment(environment) else {
            return
        }
        let statusPath: String = request.outputPath + ".status"
        do {
            let rawCatalogData: Data = try Data(
                contentsOf: URL(fileURLWithPath: request.catalogPath)
            )
            let catalogInput: VideoRuntimeAuditCatalogInput =
                try VideoRuntimeAuditCatalogInput(rawCatalogData: rawCatalogData)
            let service: VideoRuntimeAuditService = VideoRuntimeAuditService(
                runtimeFactory: self.runtimeFactory,
                webUIObserver: self.webUIObserver,
                browserRequestHeaderProvider: self.browserRequestHeaderProvider
            )
            let evidenceData: Data = try await service.run(catalogInput: catalogInput)
            try evidenceData.write(
                to: URL(fileURLWithPath: request.outputPath),
                options: .atomic
            )
            try Data("succeeded\n".utf8).write(
                to: URL(fileURLWithPath: statusPath),
                options: .atomic
            )
            #if DEBUG
            AppDebugLog.write(
                "[BrowseCraftRuntimeAudit] succeeded catalogSHA256=\(catalogInput.catalogSHA256.rawValue) bytes=\(evidenceData.count)"
            )
            #endif
        } catch {
            // 中文注释：失败标记只携带错误类型描述，不携带 URL、正文或凭据。
            let failure: String = "failed: \(String(describing: type(of: error))) \(String(describing: error))\n"
            try? Data(failure.utf8).write(
                to: URL(fileURLWithPath: statusPath),
                options: .atomic
            )
            #if DEBUG
            AppDebugLog.write("[BrowseCraftRuntimeAudit] \(failure)")
            #endif
        }
    }
}
#endif
