import Foundation

// 中文注释：HTTPClient.swift 属于领域服务协议层，用于说明本文件承载的核心职责。

/// 中文注释：应用用例层使用的最小网络请求协议。
/// 中文注释：生产环境使用 Alamofire，测试时可以替换成假的 HTTPClient。
protocol HTTPClient {
    /// 中文注释：getString 方法封装当前类型的一段业务或界面行为。
    func getString(from url: URL) async throws -> String
}

