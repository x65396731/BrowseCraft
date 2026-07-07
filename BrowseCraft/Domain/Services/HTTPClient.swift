import Foundation

// 中文注释：HTTPClient.swift 属于领域服务协议层，用于说明本文件承载的核心职责。

/// 中文注释：应用用例层使用的页面内容加载协议。
/// 中文注释：实现可以选择普通 HTTP 或 WebView 渲染后的 HTML，用例层只关心最终字符串。
protocol PageContentLoader {
    /// 中文注释：按规则解析出的请求配置抓取文本内容；配置为空时保持旧版默认 HTML 请求行为。
    func getString(from url: URL, request: RequestConfig?) async throws -> String
}

/// 中文注释：需要保留原始编码的内容使用 Data 加载，例如 RSS/XML feed。
protocol PageDataLoader {
    func getData(from url: URL, request: RequestConfig?) async throws -> Data
}

/// 中文注释：普通 HTTP 客户端仍作为独立协议存在，方便网络层和测试层表达“不会执行 JS”的实现。
protocol HTTPClient: PageContentLoader, PageDataLoader {}

extension PageContentLoader {
    /// 中文注释：旧调用点不关心页面级请求配置时，继续走默认请求，避免一次性改动所有调用方。
    func getString(from url: URL) async throws -> String {
        return try await self.getString(from: url, request: nil)
    }
}
