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

/// 中文注释：带来源上下文的文本加载协议；旧实现无需立刻迁移，运行时可按能力向下兼容。
protocol ContextualPageContentLoader: PageContentLoader {
    func getString(from url: URL, request: RequestConfig?, context: SourceRequestContext?) async throws -> String
}

/// 中文注释：带来源上下文的二进制加载协议；后续受保护资源和解密图片会从这里传递站点身份。
protocol ContextualPageDataLoader: PageDataLoader {
    func getData(from url: URL, request: RequestConfig?, context: SourceRequestContext?) async throws -> Data
}

extension PageContentLoader {
    /// 中文注释：旧调用点不关心页面级请求配置时，继续走默认请求，避免一次性改动所有调用方。
    func getString(from url: URL) async throws -> String {
        return try await self.getString(from: url, request: nil)
    }

    /// 中文注释：运行时可通过基础协议传递来源上下文；旧 loader 不支持时自动退回原请求接口。
    func getString(
        from url: URL,
        request: RequestConfig?,
        context: SourceRequestContext?
    ) async throws -> String {
        if let contextualLoader: any ContextualPageContentLoader = self as? any ContextualPageContentLoader {
            return try await contextualLoader.getString(from: url, request: request, context: context)
        }
        return try await self.getString(from: url, request: request)
    }
}

extension PageDataLoader {
    /// 中文注释：二进制资源与页面文本共享同一兼容策略，避免调用方重复做能力判断。
    func getData(
        from url: URL,
        request: RequestConfig?,
        context: SourceRequestContext?
    ) async throws -> Data {
        if let contextualLoader: any ContextualPageDataLoader = self as? any ContextualPageDataLoader {
            return try await contextualLoader.getData(from: url, request: request, context: context)
        }
        return try await self.getData(from: url, request: request)
    }
}

extension ContextualPageContentLoader {
    func getString(from url: URL, request: RequestConfig?) async throws -> String {
        return try await self.getString(from: url, request: request, context: nil)
    }
}

extension ContextualPageDataLoader {
    func getData(from url: URL, request: RequestConfig?) async throws -> Data {
        return try await self.getData(from: url, request: request, context: nil)
    }
}
