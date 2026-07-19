import Foundation

// 中文注释：RenderedPageContentLoader.swift 定义动态页面渲染 HTML 的抽象，避免应用用例直接依赖 WebKit。

/// 中文注释：只在规则声明 needsWebView 时使用，用来取得 JavaScript 执行后的最终 DOM。
protocol RenderedPageContentLoader: AnyObject {
    /// 中文注释：返回渲染完成后的 HTML 字符串；调用方仍使用既有 ComicRuleSourceParsingService 解析。
    @MainActor
    func getRenderedString(from url: URL, request: RequestConfig?) async throws -> String

    @MainActor
    func getRenderedString(
        from url: URL,
        request: RequestConfig?,
        context: SourceRequestContext?
    ) async throws -> String
}

extension RenderedPageContentLoader {
    @MainActor
    func getRenderedString(
        from url: URL,
        request: RequestConfig?,
        context: SourceRequestContext?
    ) async throws -> String {
        return try await self.getRenderedString(from: url, request: request)
    }
}
