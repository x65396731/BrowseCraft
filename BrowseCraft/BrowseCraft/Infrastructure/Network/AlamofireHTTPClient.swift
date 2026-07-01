import Alamofire
import Foundation

// 中文注释：AlamofireHTTPClient.swift 属于网络实现层，用于说明本文件承载的核心职责。

/// 中文注释：生产环境使用的 HTTP 客户端，底层由 Alamofire 实现。
final class AlamofireHTTPClient: HTTPClient {
    /// 中文注释：getString 方法封装当前类型的一段业务或界面行为。
    func getString(from url: URL) async throws -> String {
        return try await AF.request(url).serializingString().value
    }
}

