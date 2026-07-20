import Foundation

/// 中文注释：加载必须保留原始 bytes 的内容，例如 RSS/XML 与受保护资源。
protocol PageDataLoader {
    func loadData(_ request: PageLoadRequest) async throws -> PageDataResponse
}
