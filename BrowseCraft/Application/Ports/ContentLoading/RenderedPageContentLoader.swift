import Foundation

/// 中文注释：只在规则声明 needsWebView 时使用，用来取得 JavaScript 执行后的最终 DOM。
protocol RenderedPageContentLoader: AnyObject {
    /// 中文注释：返回渲染完成后的 HTML 与主 frame 最终 URL。
    @MainActor
    func loadRenderedContent(_ request: PageLoadRequest) async throws -> PageContentResponse
}
