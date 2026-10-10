import BrowseCraftDomain
import Foundation

// 中文注释：预检取页的端口、请求与错误：只有 App 实现（HTTP 与 WebView 两个加载器）和调用，
// 2026-10-10 从 BrowseCraftDomain 搬回；取回的页面值 `PreflightAcquiredPage` 与错误枚举 `PreflightPageAcquisitionError` 仍在内核：
// 前者 Runtime 的分类器消费，后者 Shared 层的埋点按类型归类（Shared 不得引用 Application）。
struct PreflightPageRequest: Hashable, Sendable {
    let url: URL
    let timeoutSeconds: TimeInterval

    init(url: URL, timeoutSeconds: TimeInterval = 12) {
        self.url = url
        self.timeoutSeconds = timeoutSeconds
    }
}

protocol PreflightPageAcquiring: Sendable {
    func acquire(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage
}

protocol PreflightRenderedPageAcquiring: Sendable {
    @MainActor
    func acquireRendered(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage
}
