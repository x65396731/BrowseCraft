import Foundation

// 中文注释：SourceRequestContext.swift 描述一次站点请求的来源和用途，供登录态、受保护资源和后续解密链路复用。

enum SourceRequestPurpose: String, Hashable {
    case list
    case search
    case detail
    case reader
    case image
    case video
    case rss
    case protectedResource
    case catalog
    case unknown
}

struct SourceRequestContext: Hashable {
    let sourceID: String?
    let baseURL: URL?
    let purpose: SourceRequestPurpose
    let refererURL: URL?
    let additionalHeaders: [String: String]
    let contextValues: [String: String]

    init(
        sourceID: String? = nil,
        baseURL: URL? = nil,
        purpose: SourceRequestPurpose = .unknown,
        refererURL: URL? = nil,
        additionalHeaders: [String: String] = [:],
        contextValues: [String: String] = [:]
    ) {
        self.sourceID = sourceID
        self.baseURL = baseURL
        self.purpose = purpose
        self.refererURL = refererURL
        self.additionalHeaders = additionalHeaders
        self.contextValues = contextValues
    }
}
