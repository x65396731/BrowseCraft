import Foundation

/// 中文注释：页面加载边界的完整输入，调用方必须显式提供 URL、规则请求配置与来源上下文。
struct PageLoadRequest {
    let url: URL
    let requestConfig: RequestConfig?
    let sourceContext: SourceRequestContext?

    init(
        url: URL,
        requestConfig: RequestConfig?,
        sourceContext: SourceRequestContext?
    ) {
        self.url = url
        self.requestConfig = requestConfig
        self.sourceContext = sourceContext
    }
}
