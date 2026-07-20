import Foundation

/// 中文注释：加载文本页面，并保留重定向或 WebView 导航后的最终 URL。
protocol PageContentLoader {
    func loadContent(_ request: PageLoadRequest) async throws -> PageContentResponse
}
